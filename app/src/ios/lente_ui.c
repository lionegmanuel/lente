#include "lente_ui.h"

#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <SDL3/SDL_video.h>

#include "events.h"
#include "util/log.h"
#include "util/thread.h"
#include "util/tick.h"

#define SC_LENTE_TITLE_MAX 256

// Main thread only
static char base_title[SC_LENTE_TITLE_MAX];
static uint32_t last_frames;
static sc_tick last_tick;
static uint8_t last_thermal;

static const char *
thermal_text(uint8_t thermal) {
    switch (thermal) {
        case 0: return "temp normal";
        case 1: return "temp tibia";
        case 2: return "temp ALTA";
        case 3: return "temp CRITICA";
        default: return "temp ?";
    }
}

static void
task_telemetry(void *userdata) {
    assert(sc_thread_is_main());
    struct sc_lente_telemetry *t = userdata;

    int count;
    SDL_Window **windows = SDL_GetWindows(&count);
    SDL_Window *window = windows && count > 0 ? windows[0] : NULL;
    SDL_free(windows);

    sc_tick now = sc_tick_now();
    unsigned fps = 0;
    if (last_tick && t->frames >= last_frames && now > last_tick) {
        fps = (unsigned) ((t->frames - last_frames) * SC_TICK_FREQ
                          / (now - last_tick));
    }
    last_frames = t->frames;
    last_tick = now;

    char battery[32];
    if (t->battery == 255) {
        snprintf(battery, sizeof(battery), "bateria ?");
    } else {
        snprintf(battery, sizeof(battery), "bateria %u%%%s",
                 (unsigned) t->battery, t->battery_state == 2 ? " cargando"
                                      : t->battery_state == 3 ? " llena" : "");
    }

    if (t->thermal >= 2 && t->thermal != last_thermal) {
        LOGW("iPhone %s: conviene bajar los cuadros por segundo o la "
             "resolucion (iPhone getting hot)", thermal_text(t->thermal));
    }
    last_thermal = t->thermal;

    if (window) {
        if (!base_title[0]) {
            const char *current = SDL_GetWindowTitle(window);
            snprintf(base_title, sizeof(base_title), "%s",
                     current && *current ? current : "Lente");
        }
        char title[SC_LENTE_TITLE_MAX * 2];
        snprintf(title, sizeof(title), "%s · %u fps · %.1f Mbps · %s · %s",
                 base_title, fps, t->bit_rate / 1e6, thermal_text(t->thermal),
                 battery);
        SDL_SetWindowTitle(window, title);
    }
    LOGD("iPhone telemetry: %u fps, %" PRIu32 " frames, %" PRIu32 " dropped, "
         "%.1f Mbps, %s, %s", fps, t->frames, t->dropped, t->bit_rate / 1e6,
         thermal_text(t->thermal), battery);
    free(t);
}

void
sc_lente_on_telemetry(const struct sc_lente_telemetry *telemetry) {
    struct sc_lente_telemetry *copy = malloc(sizeof(*copy));
    if (!copy) {
        LOG_OOM();
        return;
    }
    *copy = *telemetry;
    if (!sc_run_on_main_thread(task_telemetry, copy, false)) {
        free(copy);
    }
}

void
sc_lente_on_event(uint8_t code, char *text) {
    switch (code) {
        case 1:
            LOGW("iPhone: camara interrumpida (camera interrupted): %s", text);
            break;
        case 2:
            LOGI("iPhone: camara retomada (camera resumed)");
            break;
        case 3:
            LOGI("iPhone: lente cambiada (lens changed): %s", text);
            break;
        default:
            LOGI("iPhone: %s", text);
            break;
    }
    free(text);
}
