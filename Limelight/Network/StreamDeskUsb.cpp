#include "StreamDeskUsb.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <iterator>
#include <map>
#include <memory>
#include <thread>
#include <vector>

#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

namespace {
using Clock = std::chrono::steady_clock;
using Bytes = std::vector<uint8_t>;

constexpr int MaxLanes = 24;
constexpr size_t MaxDatagram = 16384;
constexpr std::chrono::seconds SetupTimeout(5);
constexpr uint8_t Magic[] = {'S', 'D', 'U', '1'};
constexpr int SessionKind = 0;
constexpr int TCPKind = 1;
constexpr int UDPKind = 2;
constexpr size_t LaneHeaderSize = sizeof(Magic) + 1 + sizeof(uint32_t);
constexpr int Offsets[] = {-5, 0, 21, 9, 10, 11};
constexpr size_t TCPPorts = 3;

class Fd {
public:
    explicit Fd(int value = -1) : value_(value) {}
    ~Fd() { reset(); }
    Fd(const Fd &) = delete;
    Fd &operator=(const Fd &) = delete;
    Fd(Fd &&other) noexcept : value_(other.value_) { other.value_ = -1; }
    Fd &operator=(Fd &&other) noexcept {
        reset();
        std::swap(value_, other.value_);
        return *this;
    }
    void reset() {
        if (value_ >= 0) {
            close(value_);
            value_ = -1;
        }
    }
    explicit operator bool() const { return value_ >= 0; }
    int get() const { return value_; }

private:
    int value_;
};

bool transientError() {
    return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR;
}

bool configure(int fd) {
#if defined(SO_NOSIGPIPE)
    int yes = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes)) < 0) {
        return false;
    }
#endif
    return fcntl(fd, F_SETFL, O_NONBLOCK) == 0 &&
           fcntl(fd, F_SETFD, FD_CLOEXEC) == 0;
}

Fd bindLoopback(uint16_t port, int type) {
    Fd socketFd(socket(AF_INET, type, 0));
    if (!socketFd || !configure(socketFd.get())) {
        return Fd();
    }
    if (type == SOCK_STREAM) {
        int yes = 1;
        setsockopt(socketFd.get(), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    }
    sockaddr_in addr = {};
#if defined(__APPLE__)
    addr.sin_len = sizeof(addr);
#endif
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(port);
    if (bind(socketFd.get(), reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0 ||
        (type == SOCK_STREAM && listen(socketFd.get(), MaxLanes) < 0)) {
        return Fd();
    }
    return socketFd;
}

Fd acceptConnection(int fd) {
    Fd accepted(accept(fd, nullptr, nullptr));
    if (!accepted || !configure(accepted.get())) {
        return Fd();
    }
    int yes = 1;
    setsockopt(accepted.get(), IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));
    return accepted;
}

bool flush(int fd, Bytes &bytes) {
    if (bytes.empty()) {
        return true;
    }
#if defined(MSG_NOSIGNAL)
    constexpr int flags = MSG_NOSIGNAL;
#else
    constexpr int flags = 0;
#endif
    ssize_t count = send(fd, bytes.data(), bytes.size(), flags);
    if (count <= 0) {
        return count < 0 && transientError();
    }
    bytes.erase(bytes.begin(), bytes.begin() + count);
    return true;
}

// A bounded read so a fragment never consumes bytes for the next record.
bool readUntil(int fd, Bytes &bytes, size_t size) {
    size_t previous = bytes.size();
    if (previous >= size) {
        return true;
    }
    bytes.resize(size);
    ssize_t count = recv(fd, bytes.data() + previous, size - previous, 0);
    bytes.resize(count > 0 ? previous + count : previous);
    return count > 0 || (count < 0 && transientError());
}

uint16_t read16(const uint8_t *data) {
    return static_cast<uint16_t>(data[0] << 8 | data[1]);
}

struct Pending {
    Fd socket;
    Bytes header;
    Clock::time_point expires = Clock::now() + SetupTimeout;
};

struct Lane {
    Fd local;
    Fd cable;
    // UDP lanes borrow the session's bound local socket.
    size_t endpoint = 0;
    sockaddr_in peer = {};
    Bytes outgoing;
    Bytes incoming;
    bool localEOF = false;
    bool cableEOF = false;
    bool localWriteClosed = false;
    bool cableWriteClosed = false;
    Clock::time_point expires = Clock::now() + SetupTimeout;
};

enum class WatchKind { Listener, Pending, Session, TcpEndpoint, UdpEndpoint, Local, Cable };

struct Watch {
    WatchKind kind;
    uint32_t id;
};

bool readTcp(int fd, Bytes &output, bool &eof) {
    output.resize(MaxDatagram);
    ssize_t count = recv(fd, output.data(), output.size(), 0);
    output.resize(count > 0 ? count : 0);
    eof = count == 0;
    return count >= 0 || transientError();
}

bool forwardTCP(Lane &lane, bool local, short events) {
    int fd = local ? lane.local.get() : lane.cable.get();
    Bytes &toSocket = local ? lane.incoming : lane.outgoing;
    Bytes &fromSocket = local ? lane.outgoing : lane.incoming;
    bool &eof = local ? lane.localEOF : lane.cableEOF;

    if ((events & (POLLERR | POLLNVAL)) ||
        ((events & POLLOUT) && !flush(fd, toSocket)) ||
        ((events & (POLLIN | POLLHUP)) && !eof && fromSocket.empty() &&
         !readTcp(fd, fromSocket, eof))) {
        return false;
    }

    if (lane.localEOF && lane.outgoing.empty() && !lane.cableWriteClosed) {
        shutdown(lane.cable.get(), SHUT_WR);
        lane.cableWriteClosed = true;
    }
    if (lane.cableEOF && lane.incoming.empty() && !lane.localWriteClosed) {
        shutdown(lane.local.get(), SHUT_WR);
        lane.localWriteClosed = true;
    }
    return !(lane.localWriteClosed && lane.cableWriteClosed);
}

bool forwardUDP(Lane &lane, int endpoint, short events) {
    if ((events & (POLLERR | POLLNVAL)) ||
        ((events & POLLOUT) && !flush(lane.cable.get(), lane.outgoing))) {
        return false;
    }
    if (!(events & (POLLIN | POLLHUP))) {
        return true;
    }
    Bytes &packet = lane.incoming;
    if (!readUntil(lane.cable.get(), packet, 2)) {
        return false;
    }
    if (packet.size() < 2) {
        return true;
    }
    size_t size = read16(packet.data());
    if (size == 0 || size > MaxDatagram || !readUntil(lane.cable.get(), packet, 2 + size)) {
        return false;
    }
    if (packet.size() == 2 + size) {
        // A full UDP socket may drop datagrams, just like the network path.
        sendto(endpoint, packet.data() + 2, size, 0,
               reinterpret_cast<const sockaddr *>(&lane.peer), sizeof(lane.peer));
        packet.clear();
    }
    return true;
}
}  // namespace

struct SDUsbListener {
    Fd listener;
    Fd wakeRead;
    Fd wakeWrite;
    uint16_t listenPort = 0;
    std::atomic<uint16_t> routePort{0};
    std::thread worker;

    Fd session;
    Bytes sessionOutput;
    std::array<Fd, sizeof(Offsets) / sizeof(Offsets[0])> endpoints;
    std::map<uint32_t, Pending> pending;
    std::map<uint32_t, Lane> lanes;
    uint32_t nextId = 0;

    void run();

    void resetSession() {
        routePort.store(0);
        for (auto &endpoint : endpoints) {
            endpoint.reset();
        }
        session.reset();
        sessionOutput.clear();
        lanes.clear();
        pending.clear();
    }

    bool startSession(uint16_t port, Fd &socket) {
        if (session || port < 6 || port > 65535 - Offsets[2]) {
            return false;
        }
        for (size_t index = 0; index < endpoints.size(); ++index) {
            endpoints[index] = bindLoopback(static_cast<uint16_t>(port + Offsets[index]),
                                            index < TCPPorts ? SOCK_STREAM : SOCK_DGRAM);
            if (!endpoints[index]) {
                for (auto &endpoint : endpoints) {
                    endpoint.reset();
                }
                return false;
            }
        }
        session = std::move(socket);
        sessionOutput.assign(std::begin(Magic), std::end(Magic));
        routePort.store(port);
        return true;
    }

    void acceptCable() {
        auto socket = acceptConnection(listener.get());
        if (socket && pending.size() < MaxLanes + 1) {
            Pending connection;
            connection.socket = std::move(socket);
            pending.emplace(++nextId, std::move(connection));
        }
    }

    void cableHeader(uint32_t id) {
        auto found = pending.find(id);
        if (found == pending.end()) {
            return;
        }
        Pending &connection = found->second;
        auto &header = connection.header;
        int fd = connection.socket.get();
        if (!readUntil(fd, header, LaneHeaderSize)) {
            pending.erase(found);
            return;
        }
        if (header.size() < LaneHeaderSize) {
            return;
        }
        if (!std::equal(std::begin(Magic), std::end(Magic), header.begin())) {
            pending.erase(found);
            return;
        }
        uint8_t kind = header[sizeof(Magic)];
        uint32_t channel;
        std::memcpy(&channel, header.data() + sizeof(Magic) + 1, sizeof(channel));
        channel = ntohl(channel);
        if (kind == SessionKind && channel == 0) {
            if (readUntil(fd, header, LaneHeaderSize + 2)) {
                if (header.size() < LaneHeaderSize + 2) {
                    return;
                }
                startSession(read16(header.data() + LaneHeaderSize), connection.socket);
            }
        } else {
            auto lane = lanes.find(channel);
            if (lane != lanes.end() && !lane->second.cable &&
                kind == (lane->second.local ? TCPKind : UDPKind)) {
                lane->second.cable = std::move(connection.socket);
            }
        }
        pending.erase(found);
    }

    void requestLane(Lane lane) {
        if (!session || lanes.size() >= MaxLanes || sessionOutput.size() >= MaxLanes * 6) {
            return;
        }
        uint32_t id;
        do {
            id = ++nextId;
        } while (id == 0 || lanes.count(id));
        sessionOutput.push_back(lane.local ? TCPKind : UDPKind);
        uint32_t networkId = htonl(id);
        const auto *bytes = reinterpret_cast<const uint8_t *>(&networkId);
        sessionOutput.insert(sessionOutput.end(), bytes, bytes + sizeof(networkId));
        sessionOutput.push_back(static_cast<uint8_t>(Offsets[lane.endpoint]));
        lanes.emplace(id, std::move(lane));
    }

    void acceptTCP(size_t index) {
        Lane lane;
        lane.endpoint = index;
        lane.local = acceptConnection(endpoints[index].get());
        if (lane.local) {
            requestLane(std::move(lane));
        }
    }

    void readUDP(size_t index) {
        uint8_t data[MaxDatagram + 1];
        sockaddr_in peer = {};
        socklen_t addrSize = sizeof(peer);
        ssize_t count = recvfrom(endpoints[index].get(), data, sizeof(data), 0,
                                 reinterpret_cast<sockaddr *>(&peer), &addrSize);
        if (count <= 0 || count > static_cast<ssize_t>(MaxDatagram)) {
            return;
        }
        auto existing = std::find_if(lanes.begin(), lanes.end(), [index](const std::pair<const uint32_t, Lane> &entry) {
            return entry.second.endpoint == index;
        });
        bool samePeer = existing != lanes.end() && existing->second.peer.sin_port == peer.sin_port;
        if (samePeer && !existing->second.outgoing.empty()) {
            return;
        }

        Bytes packet{static_cast<uint8_t>(count >> 8), static_cast<uint8_t>(count)};
        packet.insert(packet.end(), data, data + count);
        if (samePeer) {
            existing->second.outgoing.swap(packet);
        } else {
            if (existing != lanes.end()) {
                lanes.erase(existing);
            }
            Lane lane;
            lane.endpoint = index;
            lane.peer = peer;
            lane.outgoing.swap(packet);
            requestLane(std::move(lane));
        }
    }

    void handleLane(uint32_t id, bool local, short events) {
        auto found = lanes.find(id);
        if (found == lanes.end()) {
            return;
        }
        Lane &lane = found->second;
        bool keep = lane.local ? forwardTCP(lane, local, events)
                               : forwardUDP(lane, endpoints[lane.endpoint].get(), events);
        if (!keep) {
            lanes.erase(found);
        }
    }

    void handleSession(short events) {
        if ((events & (POLLIN | POLLERR | POLLHUP | POLLNVAL)) ||
            ((events & POLLOUT) && !flush(session.get(), sessionOutput))) {
            resetSession();
        }
    }
};

void SDUsbListener::run() {
    std::vector<pollfd> descriptors;
    std::vector<Watch> watches;
    for (;;) {
        descriptors.clear();
        watches.clear();
        auto add = [&](const Fd &fd, short events, WatchKind kind, uint32_t id = 0) {
            if (fd && events) {
                descriptors.push_back({fd.get(), events, 0});
                watches.push_back({kind, id});
            }
        };
        // The first poll entry wakes the worker immediately on stop.
        descriptors.push_back({wakeRead.get(), POLLIN, 0});
        watches.push_back({WatchKind::Listener, 0});
        add(listener, POLLIN, WatchKind::Listener);
        add(session, POLLIN | (sessionOutput.empty() ? 0 : POLLOUT), WatchKind::Session);

        bool expiring = !pending.empty();
        for (const auto &entry : pending) {
            add(entry.second.socket, POLLIN, WatchKind::Pending, entry.first);
        }
        std::array<bool, sizeof(Offsets) / sizeof(Offsets[0])> udpBuffered = {};
        for (const auto &entry : lanes) {
            const Lane &lane = entry.second;
            if (!lane.local && !lane.outgoing.empty()) {
                udpBuffered[lane.endpoint] = true;
            }
        }
        for (size_t index = 0; index < endpoints.size(); ++index) {
            if (!udpBuffered[index]) {
                add(endpoints[index], POLLIN, index < TCPPorts ? WatchKind::TcpEndpoint : WatchKind::UdpEndpoint,
                    static_cast<uint32_t>(index));
            }
        }
        for (const auto &entry : lanes) {
            const Lane &lane = entry.second;
            if (!lane.cable) {
                expiring = true;
                continue;
            }
            if (lane.local) {
                add(lane.local, (!lane.localEOF && lane.outgoing.empty() ? POLLIN : 0) |
                                (!lane.incoming.empty() ? POLLOUT : 0), WatchKind::Local, entry.first);
            }
            add(lane.cable, (!lane.cableEOF && lane.incoming.empty() ? POLLIN : 0) |
                            (!lane.outgoing.empty() ? POLLOUT : 0) |
                            (!lane.local ? POLLIN : 0), WatchKind::Cable, entry.first);
        }
        int ready = poll(descriptors.data(), descriptors.size(), expiring ? 200 : -1);
        if (ready < 0 && errno == EINTR) {
            continue;
        }
        if (ready < 0 || descriptors.front().revents) {
            break;
        }
        for (size_t index = 1; index < descriptors.size(); ++index) {
            short events = descriptors[index].revents;
            if (!events) {
                continue;
            }
            const Watch &watch = watches[index];
            switch (watch.kind) {
                case WatchKind::Listener: acceptCable(); break;
                case WatchKind::Pending: cableHeader(watch.id); break;
                case WatchKind::Session: handleSession(events); break;
                case WatchKind::TcpEndpoint:
                    if (endpoints[watch.id]) acceptTCP(watch.id);
                    break;
                case WatchKind::UdpEndpoint:
                    if (endpoints[watch.id]) readUDP(watch.id);
                    break;
                case WatchKind::Local: handleLane(watch.id, true, events); break;
                case WatchKind::Cable: handleLane(watch.id, false, events); break;
            }
        }

        if (expiring) {
            auto now = Clock::now();
            for (auto it = pending.begin(); it != pending.end();) {
                it = it->second.expires <= now ? pending.erase(it) : std::next(it);
            }
            for (auto it = lanes.begin(); it != lanes.end();) {
                it = !it->second.cable && it->second.expires <= now ? lanes.erase(it) : std::next(it);
            }
        }
    }
    resetSession();
}

SDUsbListener *SDUsbStart(uint16_t listenPort) {
    try {
        std::unique_ptr<SDUsbListener> result(new SDUsbListener);
        result->listener = bindLoopback(listenPort, SOCK_STREAM);
        if (!result->listener) {
            return nullptr;
        }
        sockaddr_in address = {};
        socklen_t size = sizeof(address);
        if (getsockname(result->listener.get(), reinterpret_cast<sockaddr *>(&address), &size) < 0) {
            return nullptr;
        }
        result->listenPort = ntohs(address.sin_port);
        int wake[2];
        if (pipe(wake) < 0) {
            return nullptr;
        }
        result->wakeRead = Fd(wake[0]);
        result->wakeWrite = Fd(wake[1]);
        result->worker = std::thread(&SDUsbListener::run, result.get());
        return result.release();
    } catch (...) {
        return nullptr;
    }
}

void SDUsbStop(SDUsbListener *listener) {
    if (!listener) {
        return;
    }
    uint8_t stop = 0;
    while (write(listener->wakeWrite.get(), &stop, 1) < 0 && errno == EINTR) {}
    listener->worker.join();
    delete listener;
}

uint16_t SDUsbListenPort(const SDUsbListener *listener) {
    return listener ? listener->listenPort : 0;
}

uint16_t SDUsbRoutePort(const SDUsbListener *listener) {
    return listener ? listener->routePort.load() : 0;
}
