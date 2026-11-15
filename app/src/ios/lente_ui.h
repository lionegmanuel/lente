#ifndef SC_LENTE_UI_H
#define SC_LENTE_UI_H

#include "common.h"

#include <stdint.h>

// Telemetry sent by the iPhone app every 2 seconds (device message 0x60)
struct sc_lente_telemetry {
    uint8_t thermal; // 0 nominal, 1 fair, 2 serious, 3 critical
    uint8_t battery; // percent, 255 unknown
    uint8_t battery_state; // 0 unknown, 1 unplugged, 2 charging, 3 full
    uint32_t frames; // encoded frames since the start of the session
    uint32_t dropped; // dropped frames since the start of the session
    uint32_t bit_rate; // measured bits per second
};

// Called from the receiver thread: shows the telemetry in the window title
// (on the main thread) and warns when the iPhone gets hot.
void
sc_lente_on_telemetry(const struct sc_lente_telemetry *telemetry);

// Called from the receiver thread with an event from the app (0x61).
// Takes ownership of text.
void
sc_lente_on_event(uint8_t code, char *text);

#endif
