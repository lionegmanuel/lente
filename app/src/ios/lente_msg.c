#include "lente_msg.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "util/binary.h"
#include "util/log.h"
#include "util/strbuf.h"

uint8_t *
sc_lnte_build_request(const char *params, size_t *len) {
    size_t n = strlen(params);
    uint8_t *buf = malloc(SC_LNTE_REQUEST_HEADER_SIZE + n);
    if (!buf) {
        LOG_OOM();
        return NULL;
    }
    memcpy(buf, "LNTE", 4);
    sc_write16be(&buf[4], SC_LNTE_VERSION);
    sc_write16be(&buf[6], 0); // flags, reserved
    sc_write32be(&buf[8], (uint32_t) n);
    memcpy(&buf[SC_LNTE_REQUEST_HEADER_SIZE], params, n);
    *len = SC_LNTE_REQUEST_HEADER_SIZE + n;
    return buf;
}

bool
sc_lnte_parse_response(const uint8_t buf[SC_LNTE_RESPONSE_HEADER_SIZE],
                       struct sc_lnte_response *response) {
    if (memcmp(buf, "LNTE", 4)) {
        return false;
    }
    response->version = sc_read16be(&buf[4]);
    response->status = buf[6];
    response->session = sc_read64be(&buf[7]);
    response->message_length = sc_read16be(&buf[15]);
    return true;
}

void
sc_lnte_build_control(uint64_t session, uint8_t buf[SC_LNTC_SIZE]) {
    memcpy(buf, "LNTC", 4);
    sc_write64be(&buf[4], session);
}

const char *
sc_lnte_status_text(uint8_t status) {
    switch (status) {
        case SC_LNTE_STATUS_OK:
            return "OK";
        case SC_LNTE_STATUS_INCOMPATIBLE_VERSION:
            return "Version incompatible: actualiza Lente en el iPhone y en la "
                   "PC (incompatible protocol version)";
        case SC_LNTE_STATUS_INVALID_PARAMETER:
            return "Parametro invalido (invalid parameter)";
        case SC_LNTE_STATUS_CAMERA_UNAVAILABLE:
            return "Camara no disponible con esa configuracion (camera not "
                   "available)";
        case SC_LNTE_STATUS_BUSY:
            return "El iPhone ya tiene otra sesion abierta (session busy)";
        case SC_LNTE_STATUS_PERMISSION_DENIED:
            return "Falta el permiso de camara: Ajustes > Lente > Camara "
                   "(camera permission denied)";
        default:
            return "Estado desconocido (unknown status)";
    }
}

static bool
append_param(struct sc_strbuf *buf, const char *key, const char *value) {
    return sc_strbuf_append_str(buf, key)
        && sc_strbuf_append_char(buf, '=')
        && sc_strbuf_append_str(buf, value)
        && sc_strbuf_append_char(buf, '\n');
}

static bool
append_param_u32(struct sc_strbuf *buf, const char *key, uint32_t value) {
    char s[16];
    snprintf(s, sizeof(s), "%" PRIu32, value);
    return append_param(buf, key, s);
}

static const char *
orientation_value(enum sc_orientation orientation) {
    switch (orientation) {
        case SC_ORIENTATION_0: return "0";
        case SC_ORIENTATION_90: return "90";
        case SC_ORIENTATION_180: return "180";
        case SC_ORIENTATION_270: return "270";
        default: return NULL; // flips are not supported by the iPhone app
    }
}

char *
sc_lente_build_params(const struct sc_server_params *params) {
    struct sc_strbuf buf;
    if (!sc_strbuf_init(&buf, 256)) {
        LOG_OOM();
        return NULL;
    }
    bool ok = true;

    switch (params->video_codec) {
        case SC_CODEC_H264:
            ok = append_param(&buf, "video_codec", "h264");
            break;
        case SC_CODEC_H265:
            ok = append_param(&buf, "video_codec", "h265");
            break;
        default:
            LOGE("The iPhone only supports --video-codec=h264 or h265");
            goto error;
    }
    if (ok && params->video_bit_rate) {
        ok = append_param_u32(&buf, "video_bit_rate", params->video_bit_rate);
    }
    if (ok && params->camera_id) {
        ok = append_param(&buf, "camera_id", params->camera_id);
    }
    if (ok && params->camera_facing != SC_CAMERA_FACING_ANY) {
        if (params->camera_facing == SC_CAMERA_FACING_EXTERNAL) {
            LOGE("The iPhone has no external camera");
            goto error;
        }
        ok = append_param(&buf, "camera_facing",
            params->camera_facing == SC_CAMERA_FACING_FRONT ? "front" : "back");
    }
    if (ok && params->camera_size) {
        ok = append_param(&buf, "camera_size", params->camera_size);
    }
    if (ok && params->camera_fps) {
        ok = append_param_u32(&buf, "camera_fps", params->camera_fps);
    }
    if (ok && params->camera_zoom) {
        ok = append_param(&buf, "camera_zoom", params->camera_zoom);
    }
    if (ok && params->camera_torch) {
        ok = append_param(&buf, "camera_torch", "true");
    }
    if (ok && params->capture_orientation != SC_ORIENTATION_0) {
        const char *o = orientation_value(params->capture_orientation);
        if (!o) {
            LOGE("The iPhone supports --capture-orientation=0, 90, 180 or 270 "
                 "(no flip)");
            goto error;
        }
        ok = append_param(&buf, "capture_orientation", o);
    }
    if (ok && params->max_fps) {
        ok = append_param(&buf, "max_fps", params->max_fps);
    }
    if (ok && !params->control) {
        ok = append_param(&buf, "control", "false");
    }
    if (ok && params->camera_stabilization) {
        ok = append_param(&buf, "lente_stabilization", "standard");
    }
    if (ok && params->keyframe_interval) {
        ok = append_param(&buf, "lente_keyframe_interval",
                          params->keyframe_interval);
    }
    if (ok && params->camera_lock) {
        const char *lock = params->camera_lock;
        if (strstr(lock, "exposure")) {
            ok = append_param(&buf, "lente_lock_exposure", "true");
        }
        if (ok && strstr(lock, "focus")) {
            ok = append_param(&buf, "lente_lock_focus", "true");
        }
        if (ok && strstr(lock, "wb")) {
            ok = append_param(&buf, "lente_lock_wb", "true");
        }
    }
    if (!ok) {
        LOG_OOM();
        goto error;
    }
    return buf.s;

error:
    free(buf.s);
    return NULL;
}
