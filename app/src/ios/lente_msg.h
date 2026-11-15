#ifndef SC_LENTE_MSG_H
#define SC_LENTE_MSG_H

#include "common.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "server.h"

// Lente session opening (LNTE) and control opening (LNTC).
// See docs/plan/ARQUITECTURA_Y_PROTOCOLO.md section 5. Big endian.

#define SC_LNTE_VERSION 1
#define SC_LNTE_REQUEST_HEADER_SIZE 12
#define SC_LNTE_RESPONSE_HEADER_SIZE 17
#define SC_LNTC_SIZE 12

enum sc_lnte_status {
    SC_LNTE_STATUS_OK = 0,
    SC_LNTE_STATUS_INCOMPATIBLE_VERSION = 1,
    SC_LNTE_STATUS_INVALID_PARAMETER = 2,
    SC_LNTE_STATUS_CAMERA_UNAVAILABLE = 3,
    SC_LNTE_STATUS_BUSY = 4,
    SC_LNTE_STATUS_PERMISSION_DENIED = 5,
};

struct sc_lnte_response {
    uint16_t version;
    uint8_t status;
    uint64_t session;
    uint16_t message_length;
};

// Build "LNTE" + version + flags + length + params. The result must be freed.
uint8_t *
sc_lnte_build_request(const char *params, size_t *len);

// Parse the fixed part of the answer. Return false if the magic is wrong.
bool
sc_lnte_parse_response(const uint8_t buf[SC_LNTE_RESPONSE_HEADER_SIZE],
                       struct sc_lnte_response *response);

// Build "LNTC" + session
void
sc_lnte_build_control(uint64_t session, uint8_t buf[SC_LNTC_SIZE]);

// Human readable explanation of a status (Spanish and English)
const char *
sc_lnte_status_text(uint8_t status);

// Session parameters sent to the iPhone app ("key=value" lines). The result
// must be freed. Return NULL on invalid parameters.
char *
sc_lente_build_params(const struct sc_server_params *params);

#endif
