#include "common.h"

#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "ios/lente_msg.h"
#include "ios/plist_min.h"
#include "ios/usbmux.h"

// Answer of a real usbmuxd (Apple Mobile Device Service) to ListDevices
static const char DEVICE_LIST[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
    "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    "<plist version=\"1.0\">\n<dict>\n"
    "\t<key>DeviceList</key>\n\t<array>\n"
    "\t\t<dict>\n"
    "\t\t\t<key>DeviceID</key>\n\t\t\t<integer>4</integer>\n"
    "\t\t\t<key>MessageType</key>\n\t\t\t<string>Attached</string>\n"
    "\t\t\t<key>Properties</key>\n\t\t\t<dict>\n"
    "\t\t\t\t<key>ConnectionSpeed</key>\n\t\t\t\t<integer>480000000</integer>\n"
    "\t\t\t\t<key>ConnectionType</key>\n\t\t\t\t<string>USB</string>\n"
    "\t\t\t\t<key>DeviceID</key>\n\t\t\t\t<integer>4</integer>\n"
    "\t\t\t\t<key>LocationID</key>\n\t\t\t\t<integer>0</integer>\n"
    "\t\t\t\t<key>ProductID</key>\n\t\t\t\t<integer>4776</integer>\n"
    "\t\t\t\t<key>SerialNumber</key>\n"
    "\t\t\t\t<string>00008130-00025DCA1A46001C</string>\n"
    "\t\t\t\t<key>UDIDs</key>\n\t\t\t\t<array/>\n"
    "\t\t\t\t<key>Extra</key>\n\t\t\t\t<data>AAEC</data>\n"
    "\t\t\t\t<key>Paired</key>\n\t\t\t\t<true/>\n"
    "\t\t\t</dict>\n"
    "\t\t</dict>\n"
    "\t\t<dict>\n"
    "\t\t\t<key>DeviceID</key>\n\t\t\t<integer>9</integer>\n"
    "\t\t\t<key>Properties</key>\n\t\t\t<dict>\n"
    "\t\t\t\t<key>ConnectionType</key>\n\t\t\t\t<string>Network</string>\n"
    "\t\t\t\t<key>SerialNumber</key>\n\t\t\t\t<string>A&amp;B</string>\n"
    "\t\t\t</dict>\n"
    "\t\t</dict>\n"
    "\t</array>\n"
    "</dict>\n</plist>\n";

static void test_plist_parse_device_list(void) {
    struct sc_usbmux_device devices[4];
    size_t count;
    bool ok = sc_usbmux_parse_device_list(DEVICE_LIST, strlen(DEVICE_LIST),
                                          devices, 4, &count);
    assert(ok);
    assert(count == 2);
    assert(devices[0].id == 4);
    assert(!strcmp(devices[0].udid, "00008130-00025DCA1A46001C"));
    assert(devices[0].product_id == 4776);
    assert(devices[0].usb);
    assert(devices[1].id == 9);
    assert(!strcmp(devices[1].udid, "A&B"));
    assert(!devices[1].usb);
}

static void test_plist_parse_result(void) {
    const char *xml = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict>"
                      "<key>MessageType</key><string>Result</string>"
                      "<key>Number</key><integer>3</integer>"
                      "</dict></plist>";
    struct sc_plist_node *plist = sc_plist_parse(xml, strlen(xml));
    assert(plist);
    assert(plist->type == SC_PLIST_DICT);
    assert(!strcmp(sc_plist_dict_get_string(plist, "MessageType"), "Result"));
    assert(sc_plist_dict_get_int(plist, "Number", -1) == 3);
    assert(sc_plist_dict_get_int(plist, "Missing", -7) == -7);
    sc_plist_free(plist);
}

static void test_plist_parse_invalid(void) {
    const char *bad[] = {
        "",
        "<plist>",
        "<plist version=\"1.0\"><dict><key>A</key></dict></plist>",
        "<plist version=\"1.0\"><dict><string>x</string></dict></plist>",
        "<plist version=\"1.0\"><integer>x</integer></plist>",
        "<plist version=\"1.0\"><dict></array></plist>",
    };
    for (size_t i = 0; i < ARRAY_LEN(bad); ++i) {
        assert(!sc_plist_parse(bad[i], strlen(bad[i])));
    }
}

static void test_plist_write_roundtrip(void) {
    struct sc_plist_entry entries[] = {
        {.key = "Text", .type = SC_PLIST_ENTRY_STRING, .string = "a<b&c>"},
        {.key = "Value", .type = SC_PLIST_ENTRY_INTEGER, .integer = -42},
    };
    size_t len;
    char *xml = sc_plist_write_dict(entries, 2, &len);
    assert(xml);
    assert(strlen(xml) == len);
    assert(strstr(xml, "<string>a&lt;b&amp;c&gt;</string>"));
    struct sc_plist_node *plist = sc_plist_parse(xml, len);
    assert(plist);
    assert(!strcmp(sc_plist_dict_get_string(plist, "Text"), "a<b&c>"));
    assert(sc_plist_dict_get_int(plist, "Value", 0) == -42);
    sc_plist_free(plist);
    free(xml);
}

static void test_usbmux_connect_request(void) {
    size_t len;
    uint8_t *msg = sc_usbmux_build_request("Connect", 4, 27183, 2, &len);
    assert(msg);
    // Little endian header: length, version 1, type 8 (plist), tag
    assert(msg[0] == (len & 0xFF) && msg[1] == ((len >> 8) & 0xFF));
    assert(msg[4] == 1 && msg[5] == 0);
    assert(msg[8] == 8 && msg[9] == 0);
    assert(msg[12] == 2);
    struct sc_plist_node *plist =
        sc_plist_parse((const char *) msg + 16, len - 16);
    assert(plist);
    assert(!strcmp(sc_plist_dict_get_string(plist, "MessageType"),
                   "Connect"));
    assert(sc_plist_dict_get_int(plist, "DeviceID", 0) == 4);
    // 27183 = 0x6A2F, sent in network byte order: 0x2F6A = 12138
    assert(sc_plist_dict_get_int(plist, "PortNumber", 0) == 12138);
    sc_plist_free(plist);
    free(msg);
}

static void test_lnte_request(void) {
    size_t len;
    uint8_t *buf = sc_lnte_build_request("camera_fps=30\n", &len);
    assert(buf);
    assert(len == 12 + 14);
    assert(!memcmp(buf, "LNTE", 4));
    assert(buf[4] == 0 && buf[5] == 1); // version 1
    assert(buf[6] == 0 && buf[7] == 0); // flags
    assert(buf[8] == 0 && buf[9] == 0 && buf[10] == 0 && buf[11] == 14);
    assert(!memcmp(&buf[12], "camera_fps=30\n", 14));
    free(buf);
}

static void test_lnte_response(void) {
    const uint8_t buf[17] = {
        'L', 'N', 'T', 'E', 0, 1, 2,
        1, 2, 3, 4, 5, 6, 7, 8,
        0, 9,
    };
    struct sc_lnte_response r;
    assert(sc_lnte_parse_response(buf, &r));
    assert(r.version == 1);
    assert(r.status == SC_LNTE_STATUS_INVALID_PARAMETER);
    assert(r.session == UINT64_C(0x0102030405060708));
    assert(r.message_length == 9);

    uint8_t bad[17] = {'X'};
    assert(!sc_lnte_parse_response(bad, &r));
}

static void test_lntc(void) {
    uint8_t buf[12];
    sc_lnte_build_control(UINT64_C(0xAB), buf);
    assert(!memcmp(buf, "LNTC", 4));
    for (int i = 4; i < 11; ++i) {
        assert(buf[i] == 0);
    }
    assert(buf[11] == 0xAB);
}

static void test_build_params(void) {
    struct sc_server_params params = {
        .video_codec = SC_CODEC_H264,
        .video_bit_rate = 24000000,
        .camera_facing = SC_CAMERA_FACING_BACK,
        .camera_size = "1920x1080",
        .camera_fps = 30,
        .capture_orientation = SC_ORIENTATION_180,
        .control = true,
        .camera_lock = "exposure,wb",
        .keyframe_interval = "1.5",
    };
    char *text = sc_lente_build_params(&params);
    assert(text);
    assert(strstr(text, "video_codec=h264\n"));
    assert(strstr(text, "video_bit_rate=24000000\n"));
    assert(strstr(text, "camera_facing=back\n"));
    assert(strstr(text, "camera_size=1920x1080\n"));
    assert(strstr(text, "camera_fps=30\n"));
    assert(strstr(text, "capture_orientation=180\n"));
    assert(strstr(text, "lente_lock_exposure=true\n"));
    assert(!strstr(text, "lente_lock_focus"));
    assert(strstr(text, "lente_lock_wb=true\n"));
    assert(strstr(text, "lente_keyframe_interval=1.5\n"));
    assert(!strstr(text, "control="));
    free(text);

    params.video_codec = SC_CODEC_AV1;
    assert(!sc_lente_build_params(&params));
    params.video_codec = SC_CODEC_H265;
    params.capture_orientation = SC_ORIENTATION_FLIP_0;
    assert(!sc_lente_build_params(&params));
    params.capture_orientation = SC_ORIENTATION_0;
    params.control = false;
    text = sc_lente_build_params(&params);
    assert(text);
    assert(strstr(text, "video_codec=h265\n"));
    assert(strstr(text, "control=false\n"));
    assert(!strstr(text, "capture_orientation"));
    free(text);
}

int main(int argc, char *argv[]) {
    (void) argc;
    (void) argv;

    test_plist_parse_device_list();
    test_plist_parse_result();
    test_plist_parse_invalid();
    test_plist_write_roundtrip();
    test_usbmux_connect_request();
    test_lnte_request();
    test_lnte_response();
    test_lntc();
    test_build_params();
    return 0;
}
