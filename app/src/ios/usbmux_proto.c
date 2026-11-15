#include "usbmux.h"

#include <stdlib.h>
#include <string.h>

#include "plist_min.h"
#include "util/binary.h"
#include "util/log.h"

// Pure usbmux message handling (no I/O), shared by usbmux.c and the tests

#define USBMUX_HEADER_SIZE 16
#define USBMUX_VERSION_PLIST 1
#define USBMUX_TYPE_PLIST 8

uint8_t *
sc_usbmux_build_request(const char *message_type, uint32_t device_id,
                        uint16_t port, uint32_t tag, size_t *len) {
    struct sc_plist_entry entries[5];
    size_t count = 0;
    entries[count++] = (struct sc_plist_entry) {
        .key = "MessageType", .type = SC_PLIST_ENTRY_STRING,
        .string = message_type,
    };
    entries[count++] = (struct sc_plist_entry) {
        .key = "ClientVersionString", .type = SC_PLIST_ENTRY_STRING,
        .string = "lente",
    };
    entries[count++] = (struct sc_plist_entry) {
        .key = "ProgName", .type = SC_PLIST_ENTRY_STRING, .string = "lente",
    };
    if (!strcmp(message_type, "Connect")) {
        entries[count++] = (struct sc_plist_entry) {
            .key = "DeviceID", .type = SC_PLIST_ENTRY_INTEGER,
            .integer = device_id,
        };
        // usbmuxd expects the port in network byte order, as an integer
        uint16_t swapped = (uint16_t) (((port & 0xFF) << 8) | (port >> 8));
        entries[count++] = (struct sc_plist_entry) {
            .key = "PortNumber", .type = SC_PLIST_ENTRY_INTEGER,
            .integer = swapped,
        };
    }

    size_t body_len;
    char *body = sc_plist_write_dict(entries, count, &body_len);
    if (!body) {
        return NULL;
    }
    size_t total = USBMUX_HEADER_SIZE + body_len;
    uint8_t *msg = malloc(total);
    if (!msg) {
        LOG_OOM();
        free(body);
        return NULL;
    }
    sc_write32le(&msg[0], (uint32_t) total);
    sc_write32le(&msg[4], USBMUX_VERSION_PLIST);
    sc_write32le(&msg[8], USBMUX_TYPE_PLIST);
    sc_write32le(&msg[12], tag);
    memcpy(&msg[USBMUX_HEADER_SIZE], body, body_len);
    free(body);
    *len = total;
    return msg;
}

void
sc_usbmux_fill_devices(const struct sc_plist_node *answer,
             struct sc_usbmux_device *devices, size_t max, size_t *count) {
    const struct sc_plist_node *list = sc_plist_dict_get(answer, "DeviceList");
    *count = 0;
    if (list && list->type == SC_PLIST_ARRAY) {
        for (const struct sc_plist_node *d = list->children;
                d && *count < max; d = d->next) {
            const struct sc_plist_node *props =
                sc_plist_dict_get(d, "Properties");
            if (!props) {
                continue;
            }
            struct sc_usbmux_device *dev = &devices[*count];
            memset(dev, 0, sizeof(*dev));
            dev->id = (uint32_t) sc_plist_dict_get_int(d, "DeviceID",
                sc_plist_dict_get_int(props, "DeviceID", 0));
            const char *udid = sc_plist_dict_get_string(props, "SerialNumber");
            if (udid) {
                strncpy(dev->udid, udid, sizeof(dev->udid) - 1);
            }
            dev->product_id =
                (uint16_t) sc_plist_dict_get_int(props, "ProductID", 0);
            const char *type =
                sc_plist_dict_get_string(props, "ConnectionType");
            dev->usb = type && !strcmp(type, "USB");
            ++*count;
        }
    }
}

bool
sc_usbmux_parse_device_list(const char *xml, size_t len,
                            struct sc_usbmux_device *devices, size_t max,
                            size_t *count) {
    struct sc_plist_node *plist = sc_plist_parse(xml, len);
    if (!plist) {
        return false;
    }
    sc_usbmux_fill_devices(plist, devices, max, count);
    sc_plist_free(plist);
    return true;
}
