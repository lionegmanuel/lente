#ifndef SC_IOS_SERVER_H
#define SC_IOS_SERVER_H

#include "common.h"

#include <stdbool.h>

#include "server.h"

// iPhone backend (Lente). Runs on the server thread instead of the adb flow:
// it opens the video and control connections through usbmux, negotiates the
// session (LNTE) and fills server->video_socket, server->control_socket and
// server->info exactly like the Android flow does.
int
sc_ios_server_run(struct sc_server *server);

// Print the iPhones seen by usbmuxd (--list-ios-devices)
bool
sc_ios_list_devices(void);

#endif
