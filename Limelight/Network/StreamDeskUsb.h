#ifndef StreamDeskUsb_h
#define StreamDeskUsb_h

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SDUsbListener SDUsbListener;

// Starts a loopback listener. Zero selects an ephemeral port for tests.
SDUsbListener *SDUsbStart(uint16_t listenPort);
void SDUsbStop(SDUsbListener *listener);
uint16_t SDUsbListenPort(const SDUsbListener *listener);
// Returns the Sunshine base port while connected, or zero while waiting.
uint16_t SDUsbRoutePort(const SDUsbListener *listener);

#ifdef __cplusplus
}
#endif

#endif
