/*
 * sdl_sensor_shim - let PICO-8 start on an SDL2 built without sensor support.
 *
 * PICO-8 is a closed commercial binary, so unlike RetroArch and PPSSPP we
 * cannot rebuild it or change what it asks SDL for. It calls SDL_Init with the
 * sensor bit set, and SDL_Init is all-or-nothing: one unavailable subsystem
 * fails the whole call. On the Anbernic XX line that is fatal:
 *
 *     SDL Error: SDL not built with sensor support
 *     ** FATAL ERROR: Unable to initialize SDL
 *
 * The awkward part is that the two SDL2 builds available to us each have
 * exactly one of the two properties PICO-8 needs, and no environment variable
 * bridges them:
 *
 *   App/PyUI/dll-mali  - enumerates the pad (it carries NextUI's H700 joystick
 *                        classification patch, needed because these pads report
 *                        no ABS_X/ABS_Y), but is built without sensors.
 *   stock Anbernic     - has sensors, but finds zero joysticks under BaseOS.
 *                        Verified with udev on, udev disabled, and with
 *                        SDL_JOYSTICK_DEVICE forcing the node: zero every time.
 *
 * Probing dll-mali subsystem by subsystem showed TIMER, AUDIO, VIDEO, JOYSTICK,
 * HAPTIC, GAMECONTROLLER and EVENTS all initialise; SENSOR alone fails. So the
 * only thing standing between PICO-8 and a fully working dll-mali is a
 * subsystem it has no use for on a handheld with no accelerometer.
 *
 * This masks the sensor bit out of SDL_Init and SDL_InitSubSystem and forwards
 * the call. Nothing else is touched, and if a future SDL2 does have sensors the
 * shim simply stops mattering - PICO-8 still never uses them.
 *
 * Built for aarch64 by .github/workflows/build-pico8-shim.yml; the source lives
 * here so the binary in lib-h700 is auditable rather than mysterious.
 */

#define _GNU_SOURCE
#include <dlfcn.h>

/* SDL_INIT_SENSOR, from SDL_init.h. Hardcoded so this needs no SDL headers. */
#define SDL_INIT_SENSOR 0x00008000u

typedef unsigned int Uint32;
typedef int (*sdl_init_fn)(Uint32);

static sdl_init_fn real_fn(const char *symbol)
{
    return (sdl_init_fn)dlsym(RTLD_NEXT, symbol);
}

int SDL_Init(Uint32 flags)
{
    sdl_init_fn real = real_fn("SDL_Init");

    /* If the real symbol cannot be found there is nothing sensible to do but
     * report failure - pretending success would strand the caller. */
    if (!real)
        return -1;

    return real(flags & ~SDL_INIT_SENSOR);
}

int SDL_InitSubSystem(Uint32 flags)
{
    sdl_init_fn real = real_fn("SDL_InitSubSystem");

    if (!real)
        return -1;

    /* Asking for sensors and nothing else is a deliberate request rather than
     * the blanket SDL_INIT_EVERYTHING, so pass it through and let it fail
     * honestly. Returning a success the caller cannot use would be worse. */
    if (flags == SDL_INIT_SENSOR)
        return real(flags);

    return real(flags & ~SDL_INIT_SENSOR);
}
