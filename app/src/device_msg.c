#include "device_msg.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "util/binary.h"
#include "util/log.h"

ssize_t
sc_device_msg_deserialize(const uint8_t *buf, size_t len,
                          struct sc_device_msg *msg) {
    if (!len) {
        return 0; // no message
    }

    msg->type = buf[0];
    switch (msg->type) {
        case DEVICE_MSG_TYPE_CLIPBOARD: {
            if (len < 5) {
                // at least type + empty string length
                return 0; // no complete message
            }
            size_t clipboard_len = sc_read32be(&buf[1]);
            if (clipboard_len > len - 5) {
                return 0; // no complete message
            }
            char *text = malloc(clipboard_len + 1);
            if (!text) {
                LOG_OOM();
                return -1;
            }
            if (clipboard_len) {
                memcpy(text, &buf[5], clipboard_len);
            }
            text[clipboard_len] = '\0';

            msg->clipboard.text = text;
            return 5 + clipboard_len;
        }
        case DEVICE_MSG_TYPE_ACK_CLIPBOARD: {
            if (len < 9) {
                return 0; // no complete message
            }
            uint64_t sequence = sc_read64be(&buf[1]);
            msg->ack_clipboard.sequence = sequence;
            return 9;
        }
        case DEVICE_MSG_TYPE_UHID_OUTPUT: {
            if (len < 5) {
                // at least id + size
                return 0; // not available
            }
            uint16_t id = sc_read16be(&buf[1]);
            size_t size = sc_read16be(&buf[3]);
            if (size > len - 5) {
                return 0; // not available
            }
            uint8_t *data = malloc(size);
            if (!data) {
                LOG_OOM();
                return -1;
            }
            if (size) {
                memcpy(data, &buf[5], size);
            }

            msg->uhid_output.id = id;
            msg->uhid_output.size = size;
            msg->uhid_output.data = data;

            return 5 + size;
        }
        case DEVICE_MSG_TYPE_LENTE_TELEMETRY:
            if (len < 16) {
                return 0; // not available
            }
            msg->lente_telemetry.thermal = buf[1];
            msg->lente_telemetry.battery = buf[2];
            msg->lente_telemetry.battery_state = buf[3];
            msg->lente_telemetry.frames = sc_read32be(&buf[4]);
            msg->lente_telemetry.dropped = sc_read32be(&buf[8]);
            msg->lente_telemetry.bit_rate = sc_read32be(&buf[12]);
            return 16;
        case DEVICE_MSG_TYPE_LENTE_EVENT: {
            if (len < 4) {
                return 0; // not available
            }
            uint16_t text_len = sc_read16be(&buf[2]);
            if (text_len > len - 4) {
                return 0; // not available
            }
            char *text = malloc(text_len + 1);
            if (!text) {
                LOG_OOM();
                return -1;
            }
            memcpy(text, &buf[4], text_len);
            text[text_len] = '\0';
            msg->lente_event.code = buf[1];
            msg->lente_event.text = text;
            return 4 + text_len;
        }
        default:
            LOGW("Unknown device message type: %d", (int) msg->type);
            return -1; // error, we cannot recover
    }
}

void
sc_device_msg_destroy(struct sc_device_msg *msg) {
    switch (msg->type) {
        case DEVICE_MSG_TYPE_CLIPBOARD:
            free(msg->clipboard.text);
            break;
        case DEVICE_MSG_TYPE_UHID_OUTPUT:
            free(msg->uhid_output.data);
            break;
        case DEVICE_MSG_TYPE_LENTE_EVENT:
            free(msg->lente_event.text);
            break;
        default:
            // nothing to do
            break;
    }
}
