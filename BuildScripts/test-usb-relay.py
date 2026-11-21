#!/usr/bin/env python3
"""Exercise the native USB listener with the Sunshine fork's relay."""

import argparse
import asyncio
import ctypes
from pathlib import Path
import runpy
import socket
import subprocess
import tempfile


async def verify_route(client, relay):
    async def tcp_response(reader, writer):
        async with relay["closing_writer"](writer):
            assert await reader.read() == b"GET /serverinfo"
            writer.write(b"serverinfo")
            await writer.drain()

    source = await asyncio.start_server(tcp_response, "127.0.0.1", 0)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as game_video:
        game_video.bind(("127.0.0.1", 0))
        game_video.setblocking(False)
        loop = asyncio.get_running_loop()
        native = client.SDUsbStart(0)
        assert native
        port = client.SDUsbListenPort(native)
        assert port > 0
        route = 49289
        actual_tcp = source.sockets[0].getsockname()[1]
        actual_udp = game_video.getsockname()[1]
        open_lane = relay["relay_lane"]

        async def forward_lane(connect_usb, kind, lane_id, endpoint):
            ports = {route: actual_tcp, route + 9: actual_udp}
            await open_lane(connect_usb, kind, lane_id, ports[endpoint])

        serve = relay["serve_relay"]
        serve.__globals__["relay_lane"] = forward_lane

        async def connect_usb():
            return await asyncio.open_connection("127.0.0.1", port)

        try:
            async with source:
                # Connect and disconnect twice, proving listeners can rebind.
                for _ in range(2):
                    async def physical_lane_test():
                        ready = asyncio.Event()
                        session = asyncio.create_task(serve(connect_usb, route, ready.set))
                        try:
                            await ready.wait()
                            assert client.SDUsbRoutePort(native) == route
                            reader, writer = await asyncio.open_connection("127.0.0.1", route)
                            async with relay["closing_writer"](writer):
                                writer.write(b"GET /serverinfo")
                                await writer.drain()
                                writer.write_eof()
                                assert await reader.read() == b"serverinfo"

                            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as iPad:
                                iPad.setblocking(False)
                                packets = (b"one frame", b"second packet", b"third")
                                for packet in packets:
                                    await loop.sock_sendto(iPad, packet, ("127.0.0.1", route + 9))
                                for packet in packets:
                                    received, sender = await loop.sock_recvfrom(game_video, 16384)
                                    assert received == packet
                                    await loop.sock_sendto(game_video, packet[::-1], sender)
                                for packet in packets:
                                    reply, peer = await loop.sock_recvfrom(iPad, 16384)
                                    assert reply == packet[::-1]
                                    assert peer == ("127.0.0.1", route + 9)
                        finally:
                            session.cancel()
                            await asyncio.gather(session, return_exceptions=True)
                            while client.SDUsbRoutePort(native):
                                await asyncio.sleep(.01)

                    await asyncio.wait_for(physical_lane_test(), 4)
        finally:
            client.SDUsbStop(native)
            serve.__globals__["relay_lane"] = open_lane


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("relay", type=Path, help="path to streamdesk-usb-relay.py from the Sunshine fork")
    args = parser.parse_args()
    cpp = Path(__file__).resolve().parent.parent / "Limelight/Network/StreamDeskUsb.cpp"
    with tempfile.TemporaryDirectory() as work:
        output = Path(work) / "streamdesk_usb.so"
        subprocess.run(["clang++", "-std=c++11", "-Wall", "-Wextra", "-Werror", "-pedantic",
                        "-pthread", "-shared", "-fPIC", str(cpp), "-o", str(output)], check=True)
        client = ctypes.CDLL(str(output))
        functions = {
            "SDUsbStart": ([ctypes.c_uint16], ctypes.c_void_p),
            "SDUsbStop": ([ctypes.c_void_p], None),
            "SDUsbListenPort": ([ctypes.c_void_p], ctypes.c_uint16),
            "SDUsbRoutePort": ([ctypes.c_void_p], ctypes.c_uint16),
        }
        for name, signature in functions.items():
            entry = getattr(client, name)
            entry.argtypes, entry.restype = signature
        asyncio.run(verify_route(client, runpy.run_path(str(args.relay))))
        print("USB listener and Sunshine relay passed TCP, UDP and reconnection checks.")


if __name__ == "__main__":
    main()
