#include "usbmux.h"

#include <assert.h>
#include <inttypes.h>
#include <stdlib.h>
#include <string.h>

#ifndef _WIN32
# include <sys/socket.h>
# include <sys/un.h>
# include <unistd.h>
#endif

#include "plist_min.h"
#include "util/binary.h"
#include "util/log.h"
#include "util/net_intr.h"

#define USBMUX_HEADER_SIZE 16
#define USBMUX_VERSION_PLIST 1
#define USBMUX_TYPE_PLIST 8
#define USBMUX_DEFAULT_UNIX_PATH "/var/run/usbmuxd"
#define USBMUX_DEFAULT_TCP_PORT 27015
#define USBMUX_MAX_BODY (1 << 20)

static inline uint32_t
read32le(const uint8_t *buf) {
    return buf[0] | (buf[1] << 8) | (buf[2] << 16)
         | ((uint32_t) buf[3] << 24);
}

const char *
sc_usbmux_install_hint(void) {
#ifdef _WIN32
    return "Install iTunes from apple.com/itunes/download/win64 (or Apple "
           "Devices from the Microsoft Store), then connect the iPhone. "
           "Instala iTunes de apple.com y conecta el iPhone.";
#else
    return "Install and start usbmuxd (tools/linux/instalar.sh), then connect "
           "the iPhone. Instala usbmuxd (tools/linux/instalar.sh) y conecta "
           "el iPhone.";
#endif
}

static sc_socket
connect_tcp(uint32_t addr, uint16_t port) {
    sc_socket socket = net_socket();
    if (socket == SC_SOCKET_NONE) {
        return SC_SOCKET_NONE;
    }
    if (!net_connect(socket, addr, port)) {
        net_close(socket);
        return SC_SOCKET_NONE;
    }
    return socket;
}

static sc_socket
connect_unix(const char *path) {
#ifdef SC_SOCKET_CLOSE_ON_INTERRUPT
    // Windows and macOS wrap sockets: Unix sockets are not supported here
    (void) path;
    LOGE("usbmux: Unix sockets are not supported on this platform, set "
         "USBMUXD_SOCKET_ADDRESS=host:port");
    return SC_SOCKET_NONE;
#else
    struct sockaddr_un sa;
    if (strlen(path) >= sizeof(sa.sun_path)) {
        LOGE("usbmux: socket path too long: %s", path);
        return SC_SOCKET_NONE;
    }
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        return SC_SOCKET_NONE;
    }
    memset(&sa, 0, sizeof(sa));
    sa.sun_family = AF_UNIX;
    strcpy(sa.sun_path, path);
    if (connect(fd, (struct sockaddr *) &sa, sizeof(sa)) < 0) {
        close(fd);
        return SC_SOCKET_NONE;
    }
    return fd;
#endif
}

static sc_socket
usbmux_open(void) {
    const char *addr = getenv("USBMUXD_SOCKET_ADDRESS");
    if (addr && *addr) {
        if (!strncmp(addr, "UNIX:", 5)) {
            return connect_unix(addr + 5);
        }
        const char *colon = strrchr(addr, ':');
        if (!colon) {
            LOGE("usbmux: invalid USBMUXD_SOCKET_ADDRESS: %s", addr);
            return SC_SOCKET_NONE;
        }
        char host[64];
        size_t n = colon - addr;
        if (n >= sizeof(host)) {
            return SC_SOCKET_NONE;
        }
        memcpy(host, addr, n);
        host[n] = '\0';
        uint32_t ipv4;
        if (!net_parse_ipv4(host, &ipv4)) {
            LOGE("usbmux: invalid host in USBMUXD_SOCKET_ADDRESS: %s", host);
            return SC_SOCKET_NONE;
        }
        long port = strtol(colon + 1, NULL, 10);
        if (port <= 0 || port > 0xFFFF) {
            return SC_SOCKET_NONE;
        }
        return connect_tcp(ipv4, (uint16_t) port);
    }
#ifdef _WIN32
    return connect_tcp(IPV4_LOCALHOST, USBMUX_DEFAULT_TCP_PORT);
#else
    return connect_unix(USBMUX_DEFAULT_UNIX_PATH);
#endif
}

static bool
send_request(struct sc_intr *intr, sc_socket socket, const char *type,
             uint32_t device_id, uint16_t port, uint32_t tag) {
    size_t len;
    uint8_t *msg = sc_usbmux_build_request(type, device_id, port, tag, &len);
    if (!msg) {
        return false;
    }
    ssize_t w = net_send_all_intr(intr, socket, msg, len);
    free(msg);
    return w == (ssize_t) len;
}

static struct sc_plist_node *
recv_answer(struct sc_intr *intr, sc_socket socket) {
    uint8_t header[USBMUX_HEADER_SIZE];
    ssize_t r = net_recv_all_intr(intr, socket, header, sizeof(header));
    if (r != (ssize_t) sizeof(header)) {
        return NULL;
    }
    uint32_t total = read32le(header);
    if (total < USBMUX_HEADER_SIZE
            || total - USBMUX_HEADER_SIZE > USBMUX_MAX_BODY) {
        LOGE("usbmux: invalid answer length %" PRIu32, total);
        return NULL;
    }
    size_t body_len = total - USBMUX_HEADER_SIZE;
    char *body = malloc(body_len + 1);
    if (!body) {
        LOG_OOM();
        return NULL;
    }
    r = net_recv_all_intr(intr, socket, body, body_len);
    if (r != (ssize_t) body_len) {
        free(body);
        return NULL;
    }
    body[body_len] = '\0';
    struct sc_plist_node *plist = sc_plist_parse(body, body_len);
    if (!plist) {
        LOGE("usbmux: could not parse the answer");
    }
    free(body);
    return plist;
}

bool
sc_usbmux_list_devices(struct sc_intr *intr, struct sc_usbmux_device *devices,
                       size_t max, size_t *count) {
    sc_socket socket = usbmux_open();
    if (socket == SC_SOCKET_NONE) {
        return false;
    }
    bool ok = send_request(intr, socket, "ListDevices", 0, 0, 1);
    struct sc_plist_node *answer = ok ? recv_answer(intr, socket) : NULL;
    net_close(socket);
    if (!answer) {
        return false;
    }

    sc_usbmux_fill_devices(answer, devices, max, count);
    sc_plist_free(answer);
    return true;
}

sc_socket
sc_usbmux_connect(struct sc_intr *intr, uint32_t device_id, uint16_t port,
                  int *result) {
    *result = -1;
    sc_socket socket = usbmux_open();
    if (socket == SC_SOCKET_NONE) {
        return SC_SOCKET_NONE;
    }
    if (!send_request(intr, socket, "Connect", device_id, port, 2)) {
        net_close(socket);
        return SC_SOCKET_NONE;
    }
    struct sc_plist_node *answer = recv_answer(intr, socket);
    if (!answer) {
        net_close(socket);
        return SC_SOCKET_NONE;
    }
    *result = (int) sc_plist_dict_get_int(answer, "Number", -1);
    sc_plist_free(answer);
    if (*result != SC_USBMUX_RESULT_OK) {
        net_close(socket);
        return SC_SOCKET_NONE;
    }
    // From now on, the socket is a raw tunnel to the device port
    return socket;
}
