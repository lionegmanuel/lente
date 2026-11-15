#include "ios_server.h"

#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ios/lente_msg.h"
#include "ios/usbmux.h"
#include "util/log.h"
#include "util/net_intr.h"
#include "util/str.h"

#define SC_IOS_DEFAULT_PORT 27183
#define SC_IOS_WAIT_APP_DELAY SC_TICK_FROM_MS(500)
#define SC_IOS_MESSAGE_MAX 1024

// Wait until the deadline or until the server is stopped.
// Return false if the server was stopped.
static bool
wait_or_stopped(struct sc_server *server, sc_tick deadline) {
    sc_mutex_lock(&server->mutex);
    bool timed_out = false;
    while (!server->stopped && !timed_out) {
        timed_out = !sc_cond_timedwait(&server->cond_stopped, &server->mutex,
                                       deadline);
    }
    bool stopped = server->stopped;
    sc_mutex_unlock(&server->mutex);
    return !stopped;
}

static bool
select_device(struct sc_server *server, struct sc_usbmux_device *out) {
    struct sc_usbmux_device devices[SC_USBMUX_MAX_DEVICES];
    size_t count;
    if (!sc_usbmux_list_devices(&server->intr, devices, ARRAY_LEN(devices),
                                &count)) {
        LOGE("Could not reach usbmuxd. %s", sc_usbmux_install_hint());
        return false;
    }
    const char *udid = server->params.ios_udid;
    for (size_t i = 0; i < count; ++i) {
        if (!devices[i].usb) {
            continue; // Lente only works by cable
        }
        if (!udid || !strcmp(udid, devices[i].udid)) {
            *out = devices[i];
            return true;
        }
    }
    if (udid) {
        LOGE("iPhone %s not found by cable (iPhone no encontrado)", udid);
    } else {
        LOGE("No iPhone connected by cable: unlock it, tap \"Trust\" and check "
             "the cable (no hay ningun iPhone conectado por cable)");
    }
    return false;
}

// Connect to the app port, waiting while the app is not open on the iPhone
static sc_socket
connect_app(struct sc_server *server, uint32_t device_id, uint16_t port,
            sc_tick wait_until) {
    bool told = false;
    for (;;) {
        int result;
        sc_socket socket =
            sc_usbmux_connect(&server->intr, device_id, port, &result);
        if (socket != SC_SOCKET_NONE) {
            return socket;
        }
        if (result != SC_USBMUX_RESULT_CONNREFUSED) {
            if (result == -1) {
                LOGE("usbmuxd connection failed. %s",
                     sc_usbmux_install_hint());
            } else {
                LOGE("usbmuxd refused the connection (code %d)", result);
            }
            return SC_SOCKET_NONE;
        }
        if (!told) {
            LOGI("Open Lente on the iPhone (abri Lente en el iPhone)...");
            told = true;
        }
        sc_tick now = sc_tick_now();
        if (now >= wait_until) {
            LOGE("Lente is not open on the iPhone (Lente no esta abierta)");
            return SC_SOCKET_NONE;
        }
        sc_tick next = now + SC_IOS_WAIT_APP_DELAY;
        if (!wait_or_stopped(server, next < wait_until ? next : wait_until)) {
            return SC_SOCKET_NONE; // stopped by the user
        }
    }
}

// Open the video connection and negotiate the session
static bool
open_video(struct sc_server *server, uint32_t device_id, uint16_t port,
           const char *params_text, uint64_t *session) {
    sc_tick wait_until = sc_tick_now() + SC_TICK_FROM_SEC(
        server->params.ios_reconnect ? server->params.ios_reconnect : 30);
    sc_socket socket = connect_app(server, device_id, port, wait_until);
    if (socket == SC_SOCKET_NONE) {
        return false;
    }

    size_t len;
    uint8_t *request = sc_lnte_build_request(params_text, &len);
    if (!request) {
        net_close(socket);
        return false;
    }
    ssize_t w = net_send_all_intr(&server->intr, socket, request, len);
    free(request);
    if (w != (ssize_t) len) {
        LOGE("Could not send the session opening to the iPhone");
        net_close(socket);
        return false;
    }

    uint8_t header[SC_LNTE_RESPONSE_HEADER_SIZE];
    ssize_t r = net_recv_all_intr(&server->intr, socket, header,
                                  sizeof(header));
    struct sc_lnte_response response;
    if (r != (ssize_t) sizeof(header)
            || !sc_lnte_parse_response(header, &response)) {
        LOGE("The iPhone app did not answer the session opening: update Lente "
             "on the iPhone (actualiza Lente en el iPhone)");
        net_close(socket);
        return false;
    }
    char message[SC_IOS_MESSAGE_MAX + 1] = "";
    if (response.message_length) {
        uint16_t n = response.message_length;
        char *tmp = malloc(n);
        if (!tmp) {
            LOG_OOM();
            net_close(socket);
            return false;
        }
        r = net_recv_all_intr(&server->intr, socket, tmp, n);
        if (r != (ssize_t) n) {
            free(tmp);
            net_close(socket);
            return false;
        }
        size_t copy = n < SC_IOS_MESSAGE_MAX ? n : SC_IOS_MESSAGE_MAX;
        memcpy(message, tmp, copy);
        message[copy] = '\0';
        free(tmp);
    }
    if (response.status != SC_LNTE_STATUS_OK) {
        LOGE("iPhone: %s: %s", sc_lnte_status_text(response.status), message);
        net_close(socket);
        return false;
    }
    LOGD("iPhone session %016" PRIx64 " (LNTE v%u)", response.session,
         (unsigned) response.version);

    // Same as Android: the first socket carries the device name
    uint8_t name[SC_DEVICE_NAME_FIELD_LENGTH];
    r = net_recv_all_intr(&server->intr, socket, name, sizeof(name));
    if (r != (ssize_t) sizeof(name)) {
        LOGE("Could not read the iPhone name");
        net_close(socket);
        return false;
    }
    name[SC_DEVICE_NAME_FIELD_LENGTH - 1] = '\0';
    memcpy(server->info.device_name, name, sizeof(name));

    server->video_socket = socket;
    *session = response.session;
    return true;
}

static bool
open_control(struct sc_server *server, uint32_t device_id, uint16_t port,
             uint64_t session) {
    int result;
    sc_socket socket = sc_usbmux_connect(&server->intr, device_id, port,
                                         &result);
    if (socket == SC_SOCKET_NONE) {
        LOGE("Could not open the control connection (code %d)", result);
        return false;
    }
    uint8_t buf[SC_LNTC_SIZE];
    sc_lnte_build_control(session, buf);
    if (net_send_all_intr(&server->intr, socket, buf, sizeof(buf))
            != (ssize_t) sizeof(buf)) {
        net_close(socket);
        return false;
    }
    server->control_socket = socket;
    return true;
}

int
sc_ios_server_run(struct sc_server *server) {
    const struct sc_server_params *params = &server->params;
    uint16_t port = params->ios_port ? params->ios_port : SC_IOS_DEFAULT_PORT;

    if (params->list) {
        LOGE("--list-* options are not available with the iPhone: the app "
             "uses fixed lenses (0: 0.5x, 1: 1x, 2: 5x, 3: front)");
        goto error_connection_failed;
    }

    char *params_text = sc_lente_build_params(params);
    if (!params_text) {
        goto error_connection_failed;
    }

    struct sc_usbmux_device device;
    if (!select_device(server, &device)) {
        free(params_text);
        goto error_connection_failed;
    }
    server->serial = strdup(device.udid);
    if (!server->serial) {
        LOG_OOM();
        free(params_text);
        goto error_connection_failed;
    }
    LOGI("iPhone: %s (usbmux device %" PRIu32 ")", device.udid, device.id);

    uint64_t session;
    bool ok = open_video(server, device.id, port, params_text, &session);
    free(params_text);
    if (!ok) {
        goto error_connection_failed;
    }

    if (params->control && !open_control(server, device.id, port, session)) {
        net_close(server->video_socket);
        server->video_socket = SC_SOCKET_NONE;
        goto error_connection_failed;
    }

    server->cbs->on_connected(server, server->cbs_userdata);

    // Wait for sc_server_stop()
    sc_mutex_lock(&server->mutex);
    while (!server->stopped) {
        sc_cond_wait(&server->cond_stopped, &server->mutex);
    }
    sc_mutex_unlock(&server->mutex);

    if (server->video_socket != SC_SOCKET_NONE) {
        net_interrupt(server->video_socket);
    }
    if (server->control_socket != SC_SOCKET_NONE) {
        net_interrupt(server->control_socket);
    }
    return 0;

error_connection_failed:
    server->cbs->on_connection_failed(server, server->cbs_userdata);
    return -1;
}

bool
sc_ios_list_devices(void) {
    struct sc_intr intr;
    if (!sc_intr_init(&intr)) {
        return false;
    }
    struct sc_usbmux_device devices[SC_USBMUX_MAX_DEVICES];
    size_t count;
    bool ok = sc_usbmux_list_devices(&intr, devices, ARRAY_LEN(devices),
                                     &count);
    sc_intr_destroy(&intr);
    if (!ok) {
        LOGE("Could not reach usbmuxd. %s", sc_usbmux_install_hint());
        return false;
    }
    if (!count) {
        LOGI("No iPhone found (no hay ningun iPhone conectado)");
        return true;
    }
    LOGI("List of iPhones:");
    for (size_t i = 0; i < count; ++i) {
        LOGI("    --ios-udid=%-40s (%s, product 0x%04x)", devices[i].udid,
             devices[i].usb ? "USB" : "network",
             (unsigned) devices[i].product_id);
    }
    return true;
}
