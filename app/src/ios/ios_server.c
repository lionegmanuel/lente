#include "ios_server.h"

#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ios/lente_msg.h"
#include "ios/usbmux.h"
#include "util/binary.h"
#include "util/log.h"
#include "util/net_intr.h"
#include "util/thread.h"

#define SC_IOS_DEFAULT_PORT 27183
#define SC_IOS_WAIT_APP_DELAY SC_TICK_FROM_MS(500)
#define SC_IOS_MESSAGE_MAX 1024
#define SC_IOS_CODEC_META_SIZE 4
#define SC_IOS_PACKET_HEADER_SIZE 12
#define SC_IOS_FLAG_SESSION (UINT64_C(1) << 63)
#define SC_IOS_FLAG_CONFIG (UINT64_C(1) << 62)
#define SC_IOS_PTS_MASK ((UINT64_C(1) << 61) - 1)
#define SC_IOS_FRAME_GAP_US 33333
#define SC_IOS_COPY_CHUNK 65536
#define SC_IOS_LOCAL_PORT_FIRST 27300
#define SC_IOS_LOCAL_PORT_LAST 27399

// An open session with the iPhone app
struct sc_ios_session {
    sc_socket video; // positioned after the codec meta (next: session packet)
    sc_socket control; // SC_SOCKET_NONE without control
    uint64_t id;
    uint8_t codec_meta[SC_IOS_CODEC_META_SIZE];
};

// Bridge between the iPhone and scrcpy, so that the window, the V4L2 sink and
// the recording stay open while the iPhone reconnects (Lente, phase 4)
struct sc_ios_link {
    struct sc_server *server;
    uint16_t port;
    const char *params_text;
    char udid[SC_USBMUX_UDID_LENGTH];

    sc_mutex mutex;
    sc_cond cond;
    bool stopped;
    unsigned generation;
    sc_socket phone_video;
    sc_socket phone_control;

    sc_socket local_video; // the bridge writes the stream here
    sc_socket local_control; // the bridge relays control here

    sc_thread video_thread;
    sc_thread control_up_thread;
    sc_thread control_down_thread;
    bool has_control;

    uint64_t last_pts;
    int64_t pts_offset;
    bool rebase_pts;

    // Dropped iPhone sockets: interrupted at once, closed only at the end,
    // when no thread can use them anymore (on Windows, closing frees them)
    sc_socket retired[64];
    size_t retired_count;
};

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
select_device(struct sc_server *server, const char *udid, bool quiet,
              struct sc_usbmux_device *out) {
    struct sc_usbmux_device devices[SC_USBMUX_MAX_DEVICES];
    size_t count;
    if (!sc_usbmux_list_devices(&server->intr, devices, ARRAY_LEN(devices),
                                &count)) {
        if (!quiet) {
            LOGE("Could not reach usbmuxd. %s", sc_usbmux_install_hint());
        }
        return false;
    }
    for (size_t i = 0; i < count; ++i) {
        if (!devices[i].usb) {
            continue; // Lente only works by cable
        }
        if (!udid || !strcmp(udid, devices[i].udid)) {
            *out = devices[i];
            return true;
        }
    }
    if (!quiet) {
        if (udid) {
            LOGE("iPhone %s not found by cable (iPhone no encontrado)", udid);
        } else {
            LOGE("No iPhone connected by cable: unlock it, tap \"Trust\" and "
                 "check the cable (no hay ningun iPhone conectado por cable)");
        }
    }
    return false;
}

// Connect to the app port, waiting while the app is not open on the iPhone
static sc_socket
connect_app(struct sc_server *server, uint32_t device_id, uint16_t port,
            sc_tick wait_until, bool quiet) {
    bool told = quiet;
    for (;;) {
        int result;
        sc_socket socket =
            sc_usbmux_connect(&server->intr, device_id, port, &result);
        if (socket != SC_SOCKET_NONE) {
            return socket;
        }
        if (result != SC_USBMUX_RESULT_CONNREFUSED) {
            if (!quiet) {
                if (result == -1) {
                    LOGE("usbmuxd connection failed. %s",
                         sc_usbmux_install_hint());
                } else {
                    LOGE("usbmuxd refused the connection (code %d)", result);
                }
            }
            return SC_SOCKET_NONE;
        }
        if (!told) {
            LOGI("Open Lente on the iPhone (abri Lente en el iPhone)...");
            told = true;
        }
        sc_tick now = sc_tick_now();
        if (now >= wait_until) {
            if (!quiet) {
                LOGE("Lente is not open on the iPhone (Lente no esta abierta)");
            }
            return SC_SOCKET_NONE;
        }
        sc_tick next = now + SC_IOS_WAIT_APP_DELAY;
        if (!wait_or_stopped(server, next < wait_until ? next : wait_until)) {
            return SC_SOCKET_NONE; // stopped by the user
        }
    }
}

static bool
recv_exact(struct sc_server *server, sc_socket socket, void *buf, size_t len) {
    return net_recv_all_intr(&server->intr, socket, buf, len) == (ssize_t) len;
}

// Open the video connection, negotiate the session (LNTE), read the device
// name and the codec meta, then open the control connection if needed.
static bool
open_session(struct sc_server *server, uint32_t device_id, uint16_t port,
             const char *params_text, sc_tick wait_until, bool quiet,
             char name[SC_DEVICE_NAME_FIELD_LENGTH],
             struct sc_ios_session *session) {
    sc_socket video = connect_app(server, device_id, port, wait_until, quiet);
    if (video == SC_SOCKET_NONE) {
        return false;
    }

    size_t len;
    uint8_t *request = sc_lnte_build_request(params_text, &len);
    if (!request) {
        net_close(video);
        return false;
    }
    ssize_t w = net_send_all_intr(&server->intr, video, request, len);
    free(request);
    if (w != (ssize_t) len) {
        LOGE("Could not send the session opening to the iPhone");
        net_close(video);
        return false;
    }

    uint8_t header[SC_LNTE_RESPONSE_HEADER_SIZE];
    struct sc_lnte_response response;
    if (!recv_exact(server, video, header, sizeof(header))
            || !sc_lnte_parse_response(header, &response)) {
        LOGE("The iPhone app did not answer the session opening: update Lente "
             "on the iPhone (actualiza Lente en el iPhone)");
        net_close(video);
        return false;
    }
    char message[SC_IOS_MESSAGE_MAX + 1] = "";
    if (response.message_length) {
        uint16_t n = response.message_length;
        char *tmp = malloc(n);
        if (!tmp) {
            LOG_OOM();
            net_close(video);
            return false;
        }
        if (!recv_exact(server, video, tmp, n)) {
            free(tmp);
            net_close(video);
            return false;
        }
        size_t copy = n < SC_IOS_MESSAGE_MAX ? n : SC_IOS_MESSAGE_MAX;
        memcpy(message, tmp, copy);
        message[copy] = '\0';
        free(tmp);
    }
    if (response.status != SC_LNTE_STATUS_OK) {
        LOGE("iPhone: %s: %s", sc_lnte_status_text(response.status), message);
        net_close(video);
        return false;
    }

    // Same as Android: the first socket carries the device name, then the
    // codec meta
    uint8_t raw_name[SC_DEVICE_NAME_FIELD_LENGTH];
    if (!recv_exact(server, video, raw_name, sizeof(raw_name))
            || !recv_exact(server, video, session->codec_meta,
                           SC_IOS_CODEC_META_SIZE)) {
        LOGE("Could not read the iPhone stream header");
        net_close(video);
        return false;
    }
    raw_name[SC_DEVICE_NAME_FIELD_LENGTH - 1] = '\0';
    memcpy(name, raw_name, sizeof(raw_name));

    session->video = video;
    session->control = SC_SOCKET_NONE;
    session->id = response.session;
    LOGD("iPhone session %016" PRIx64 " (LNTE v%u)", response.session,
         (unsigned) response.version);

    if (server->params.control) {
        int result;
        sc_socket control = sc_usbmux_connect(&server->intr, device_id, port,
                                              &result);
        if (control == SC_SOCKET_NONE) {
            LOGE("Could not open the control connection (code %d)", result);
            net_close(video);
            return false;
        }
        uint8_t lntc[SC_LNTC_SIZE];
        sc_lnte_build_control(response.session, lntc);
        if (net_send_all_intr(&server->intr, control, lntc, sizeof(lntc))
                != (ssize_t) sizeof(lntc)) {
            net_close(control);
            net_close(video);
            return false;
        }
        session->control = control;
    }
    return true;
}

// Connected pair of local TCP sockets (works on Windows too, unlike
// socketpair())
static bool
make_local_pair(sc_socket *a, sc_socket *b) {
    sc_socket listener = net_socket();
    if (listener == SC_SOCKET_NONE) {
        return false;
    }
    uint16_t port = 0;
    for (uint16_t p = SC_IOS_LOCAL_PORT_FIRST; p <= SC_IOS_LOCAL_PORT_LAST;
            ++p) {
        if (net_listen(listener, IPV4_LOCALHOST, p, 1)) {
            port = p;
            break;
        }
    }
    if (!port) {
        LOGE("Could not open a local port for the iPhone bridge");
        net_close(listener);
        return false;
    }
    sc_socket client = net_socket();
    if (client == SC_SOCKET_NONE || !net_connect(client, IPV4_LOCALHOST, port)) {
        if (client != SC_SOCKET_NONE) {
            net_close(client);
        }
        net_close(listener);
        return false;
    }
    sc_socket accepted = net_accept(listener);
    net_close(listener);
    if (accepted == SC_SOCKET_NONE) {
        net_close(client);
        return false;
    }
    net_set_tcp_nodelay(client, true);
    net_set_tcp_nodelay(accepted, true);
    *a = accepted;
    *b = client;
    return true;
}

static struct sc_ios_link link;

static bool
link_stopped(void) {
    sc_mutex_lock(&link.mutex);
    bool stopped = link.stopped;
    sc_mutex_unlock(&link.mutex);
    return stopped;
}

// Copy len bytes from the iPhone to scrcpy. Return 0 on success, -1 if the
// iPhone side failed, -2 if the scrcpy side failed.
static int
forward(sc_socket from, sc_socket to, size_t len, uint8_t *buf) {
    while (len) {
        size_t n = len < SC_IOS_COPY_CHUNK ? len : SC_IOS_COPY_CHUNK;
        if (net_recv_all(from, buf, n) != (ssize_t) n) {
            return -1;
        }
        if (net_send_all(to, buf, n) != (ssize_t) n) {
            return -2;
        }
        len -= n;
    }
    return 0;
}

// Wait for the iPhone again (same UDID, the usbmux device id may change)
static bool
reconnect(void) {
    struct sc_server *server = link.server;
    uint16_t seconds = server->params.ios_reconnect;
    sc_tick deadline = sc_tick_now() + SC_TICK_FROM_SEC(seconds);
    LOGW("iPhone desconectado: esperando hasta %u s a que vuelva (open Lente "
         "on the iPhone and check the cable)", (unsigned) seconds);
    while (!link_stopped()) {
        struct sc_usbmux_device device;
        if (select_device(server, link.udid, true, &device)) {
            char name[SC_DEVICE_NAME_FIELD_LENGTH];
            struct sc_ios_session session;
            sc_tick until = sc_tick_now() + SC_TICK_FROM_SEC(1);
            if (open_session(server, device.id, link.port, link.params_text,
                             until, true, name, &session)) {
                sc_mutex_lock(&link.mutex);
                link.phone_video = session.video;
                link.phone_control = session.control;
                ++link.generation;
                link.rebase_pts = true;
                sc_cond_broadcast(&link.cond);
                sc_mutex_unlock(&link.mutex);
                LOGI("iPhone reconectado (reconnected)");
                return true;
            }
        }
        sc_tick now = sc_tick_now();
        if (now >= deadline) {
            LOGE("El iPhone no volvio en %u s (iPhone did not come back)",
                 (unsigned) seconds);
            return false;
        }
        sc_tick next = now + SC_TICK_FROM_SEC(1);
        if (!wait_or_stopped(server, next < deadline ? next : deadline)) {
            return false;
        }
    }
    return false;
}

// Must be called with the mutex locked
static void
retire_locked(sc_socket socket) {
    if (socket == SC_SOCKET_NONE) {
        return;
    }
    net_interrupt(socket); // wake up any reader
    if (link.retired_count < ARRAY_LEN(link.retired)) {
        link.retired[link.retired_count++] = socket;
    } else {
        net_close(socket); // more than 64 reconnections: very unlikely
    }
}

static void
drop_phone(void) {
    sc_mutex_lock(&link.mutex);
    retire_locked(link.phone_video);
    retire_locked(link.phone_control);
    link.phone_video = SC_SOCKET_NONE;
    link.phone_control = SC_SOCKET_NONE;
    sc_mutex_unlock(&link.mutex);
}

static int
run_video_bridge(void *data) {
    (void) data;
    uint8_t *buf = malloc(SC_IOS_COPY_CHUNK);
    if (!buf) {
        LOG_OOM();
        goto end;
    }

    for (;;) {
        sc_mutex_lock(&link.mutex);
        sc_socket phone = link.phone_video;
        sc_mutex_unlock(&link.mutex);
        if (phone == SC_SOCKET_NONE) {
            break;
        }

        uint8_t header[SC_IOS_PACKET_HEADER_SIZE];
        if (net_recv_all(phone, header, sizeof(header))
                != (ssize_t) sizeof(header)) {
            goto phone_lost;
        }
        uint64_t flags = sc_read64be(header);
        if (!(flags & SC_IOS_FLAG_SESSION) && !(flags & SC_IOS_FLAG_CONFIG)) {
            // Keep the timestamps increasing across reconnections
            uint64_t pts = flags & SC_IOS_PTS_MASK;
            if (link.rebase_pts) {
                link.pts_offset = (int64_t) (link.last_pts + SC_IOS_FRAME_GAP_US)
                                - (int64_t) pts;
                link.rebase_pts = false;
            }
            int64_t out = (int64_t) pts + link.pts_offset;
            uint64_t out_pts = out > 0 ? (uint64_t) out : 0;
            link.last_pts = out_pts;
            flags = (flags & ~SC_IOS_PTS_MASK) | (out_pts & SC_IOS_PTS_MASK);
            sc_write64be(header, flags);
        }
        if (net_send_all(link.local_video, header, sizeof(header))
                != (ssize_t) sizeof(header)) {
            break; // scrcpy closed
        }
        if (!(flags & SC_IOS_FLAG_SESSION)) {
            uint32_t len = sc_read32be(&header[8]);
            int r = forward(phone, link.local_video, len, buf);
            if (r == -2) {
                break;
            }
            if (r == -1) {
                // The packet header already went out: the stream would be
                // corrupted, so the reconnection is not possible here
                LOGE("iPhone desconectado en medio de un cuadro");
                drop_phone();
                break;
            }
        }
        continue;

phone_lost:
        drop_phone();
        if (link_stopped() || !link.server->params.ios_reconnect
                || !reconnect()) {
            break;
        }
    }

end:
    free(buf);
    // End of stream for scrcpy: the demuxer sees the end and closes
    net_interrupt(link.local_video);
    sc_mutex_lock(&link.mutex);
    link.stopped = true;
    sc_cond_broadcast(&link.cond);
    sc_mutex_unlock(&link.mutex);
    return 0;
}

// iPhone to scrcpy: telemetry and events
static int
run_control_down(void *data) {
    (void) data;
    uint8_t buf[4096];
    for (;;) {
        sc_mutex_lock(&link.mutex);
        while (!link.stopped && link.phone_control == SC_SOCKET_NONE) {
            sc_cond_wait(&link.cond, &link.mutex);
        }
        bool stopped = link.stopped;
        sc_socket phone = link.phone_control;
        unsigned generation = link.generation;
        sc_mutex_unlock(&link.mutex);
        if (stopped) {
            break;
        }
        ssize_t r = net_recv(phone, buf, sizeof(buf));
        if (r <= 0) {
            // Wait for the next session (the video bridge reconnects)
            sc_mutex_lock(&link.mutex);
            while (!link.stopped && link.generation == generation) {
                sc_cond_wait(&link.cond, &link.mutex);
            }
            sc_mutex_unlock(&link.mutex);
            continue;
        }
        if (net_send_all(link.local_control, buf, r) != r) {
            break;
        }
    }
    return 0;
}

// scrcpy to iPhone: controls (lost while the iPhone is disconnected)
static int
run_control_up(void *data) {
    (void) data;
    uint8_t buf[4096];
    for (;;) {
        ssize_t r = net_recv(link.local_control, buf, sizeof(buf));
        if (r <= 0) {
            break;
        }
        sc_mutex_lock(&link.mutex);
        sc_socket phone = link.phone_control;
        sc_mutex_unlock(&link.mutex);
        if (phone != SC_SOCKET_NONE) {
            net_send_all(phone, buf, r);
        }
    }
    return 0;
}

static bool
start_bridge(struct sc_server *server, struct sc_ios_session *session) {
    if (!sc_mutex_init(&link.mutex)) {
        return false;
    }
    if (!sc_cond_init(&link.cond)) {
        sc_mutex_destroy(&link.mutex);
        return false;
    }
    link.phone_video = session->video;
    link.phone_control = session->control;
    link.has_control = session->control != SC_SOCKET_NONE;

    sc_socket scrcpy_video, scrcpy_control = SC_SOCKET_NONE;
    if (!make_local_pair(&link.local_video, &scrcpy_video)) {
        goto error_cond;
    }
    // The codec meta was read with the session: scrcpy reads it from here
    if (net_send_all(link.local_video, session->codec_meta,
                     SC_IOS_CODEC_META_SIZE) != SC_IOS_CODEC_META_SIZE) {
        goto error_video;
    }
    if (link.has_control
            && !make_local_pair(&link.local_control, &scrcpy_control)) {
        goto error_video;
    }

    if (!sc_thread_create(&link.video_thread, run_video_bridge,
                          "lente-video", NULL)) {
        goto error_control;
    }
    if (link.has_control) {
        if (!sc_thread_create(&link.control_down_thread, run_control_down,
                              "lente-ctl-down", NULL)) {
            goto error_control; // the video thread ends with the server
        }
        if (!sc_thread_create(&link.control_up_thread, run_control_up,
                              "lente-ctl-up", NULL)) {
            goto error_control;
        }
    }
    server->video_socket = scrcpy_video;
    server->control_socket = scrcpy_control;
    return true;

error_control:
    if (scrcpy_control != SC_SOCKET_NONE) {
        net_close(scrcpy_control);
        net_close(link.local_control);
    }
error_video:
    net_close(scrcpy_video);
    net_close(link.local_video);
error_cond:
    sc_cond_destroy(&link.cond);
    sc_mutex_destroy(&link.mutex);
    return false;
}

static void
stop_bridge(void) {
    sc_mutex_lock(&link.mutex);
    link.stopped = true;
    sc_cond_broadcast(&link.cond);
    if (link.phone_video != SC_SOCKET_NONE) {
        net_interrupt(link.phone_video);
    }
    if (link.phone_control != SC_SOCKET_NONE) {
        net_interrupt(link.phone_control);
    }
    sc_mutex_unlock(&link.mutex);

    net_interrupt(link.local_video);
    if (link.has_control) {
        net_interrupt(link.local_control);
    }

    sc_thread_join(&link.video_thread, NULL);
    if (link.has_control) {
        sc_thread_join(&link.control_down_thread, NULL);
        sc_thread_join(&link.control_up_thread, NULL);
    }
    drop_phone();
    for (size_t i = 0; i < link.retired_count; ++i) {
        net_close(link.retired[i]);
    }
    net_close(link.local_video);
    if (link.has_control) {
        net_close(link.local_control);
    }
    sc_cond_destroy(&link.cond);
    sc_mutex_destroy(&link.mutex);
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
    if (!select_device(server, params->ios_udid, false, &device)) {
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

    sc_tick wait_until = sc_tick_now() + SC_TICK_FROM_SEC(
        params->ios_reconnect ? params->ios_reconnect : 30);
    struct sc_ios_session session;
    if (!open_session(server, device.id, port, params_text, wait_until, false,
                      server->info.device_name, &session)) {
        free(params_text);
        goto error_connection_failed;
    }

    memset(&link, 0, sizeof(link));
    link.server = server;
    link.port = port;
    link.params_text = params_text;
    snprintf(link.udid, sizeof(link.udid), "%s", device.udid);

    if (!start_bridge(server, &session)) {
        if (session.control != SC_SOCKET_NONE) {
            net_close(session.control);
        }
        net_close(session.video);
        free(params_text);
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
    stop_bridge();
    free(params_text);
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
