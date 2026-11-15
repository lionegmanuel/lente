#ifndef SC_USBMUX_H
#define SC_USBMUX_H

#include "common.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "util/intr.h"
#include "util/net.h"

// usbmuxd client (protocol version 1, XML plist messages), written for Lente.
// Windows: Apple Mobile Device Service on 127.0.0.1:27015.
// Linux: Unix socket /var/run/usbmuxd.
// USBMUXD_SOCKET_ADDRESS overrides it ("UNIX:/path" or "host:port").

#define SC_USBMUX_UDID_LENGTH 64
#define SC_USBMUX_MAX_DEVICES 16

// usbmuxd result codes
#define SC_USBMUX_RESULT_OK 0
#define SC_USBMUX_RESULT_BADDEV 2
#define SC_USBMUX_RESULT_CONNREFUSED 3

struct sc_usbmux_device {
    uint32_t id;
    char udid[SC_USBMUX_UDID_LENGTH];
    uint16_t product_id;
    bool usb; // false: network
};

// List the devices known to usbmuxd. Return false if usbmuxd is unreachable.
bool
sc_usbmux_list_devices(struct sc_intr *intr, struct sc_usbmux_device *devices,
                       size_t max, size_t *count);

// Open a tunnel to a TCP port of the device. On success, the returned socket
// is connected to the device port. On failure, return SC_SOCKET_NONE and set
// *result to the usbmuxd result code (or -1 if usbmuxd is unreachable).
sc_socket
sc_usbmux_connect(struct sc_intr *intr, uint32_t device_id, uint16_t port,
                  int *result);

// Hint for the user when usbmuxd is unreachable
const char *
sc_usbmux_install_hint(void);

// Serialize a request (header + plist body). Exposed for tests.
uint8_t *
sc_usbmux_build_request(const char *message_type, uint32_t device_id,
                        uint16_t port, uint32_t tag, size_t *len);

struct sc_plist_node;

// Fill devices from a parsed ListDevices answer
void
sc_usbmux_fill_devices(const struct sc_plist_node *answer,
                       struct sc_usbmux_device *devices, size_t max,
                       size_t *count);

// Parse a ListDevices answer body. Exposed for tests.
bool
sc_usbmux_parse_device_list(const char *xml, size_t len,
                            struct sc_usbmux_device *devices, size_t max,
                            size_t *count);

#endif
