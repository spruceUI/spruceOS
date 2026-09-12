#!/usr/bin/env python3

"""
Talk to GBM and EGL directly, without SDL in the way.

Every SDL permutation fails identically at "Can't window GBM/EGL surfaces",
which is SDL's KMSDRM backend reporting that KMSDRM_CreateSurfaces() failed.
That function does three things: choose an EGL config, read its native visual
id, and call gbm_surface_create() with that id as the format. Any of the three
can be the one breaking, and SDL collapses all of them into one message.

So do the three steps by hand and report each separately, plus which formats
this Mali GBM will actually accept for scanout. That turns "graphics do not
work" into a specific fourcc.

Prints KEY=VALUE lines. Never fails the boot - the caller only reads it.
"""

import ctypes
import os
import sys


def fourcc(code):
    a, b, c, d = code
    return ord(a) | (ord(b) << 8) | (ord(c) << 16) | (ord(d) << 24)


# The formats worth asking about, with the two SDL actually tries first.
FORMATS = [
    ("ARGB8888", fourcc("AR24")),
    ("XRGB8888", fourcc("XR24")),
    ("ABGR8888", fourcc("AB24")),
    ("XBGR8888", fourcc("XB24")),
    ("RGB565", fourcc("RG16")),
    ("ARGB2101010", fourcc("AR30")),
    ("XRGB2101010", fourcc("XR30")),
]

GBM_BO_USE_SCANOUT = 1
GBM_BO_USE_RENDERING = 4

# What SDL's KMSDRM backend asks for.
SDL_USAGE = GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING

EGL_SUCCESS = 0x3000
EGL_NO_DISPLAY = 0
EGL_SURFACE_TYPE = 0x3033
EGL_WINDOW_BIT = 0x0004
EGL_RENDERABLE_TYPE = 0x3040
EGL_OPENGL_ES2_BIT = 0x0004
EGL_RED_SIZE = 0x3024
EGL_GREEN_SIZE = 0x3023
EGL_BLUE_SIZE = 0x3022
EGL_ALPHA_SIZE = 0x3021
EGL_DEPTH_SIZE = 0x3025
EGL_NATIVE_VISUAL_ID = 0x302E
EGL_NONE = 0x3038
EGL_PLATFORM_GBM_KHR = 0x31D7


def report(key, value):
    print(f"{key}={value}")
    sys.stdout.flush()


def main():
    card = os.environ.get("RGB30_DRM_NODE", "/dev/dri/card0")

    try:
        gbm = ctypes.CDLL("libgbm.so.1")
    except OSError as exc:
        report("RESULT", "NO_GBM")
        report("ERROR", exc)
        return 0

    try:
        egl = ctypes.CDLL("libEGL.so.1")
    except OSError as exc:
        report("RESULT", "NO_EGL")
        report("ERROR", exc)
        return 0

    gbm.gbm_create_device.restype = ctypes.c_void_p
    gbm.gbm_create_device.argtypes = [ctypes.c_int]
    gbm.gbm_device_is_format_supported.restype = ctypes.c_int
    gbm.gbm_device_is_format_supported.argtypes = [
        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32
    ]
    gbm.gbm_surface_create.restype = ctypes.c_void_p
    gbm.gbm_surface_create.argtypes = [
        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32,
        ctypes.c_uint32, ctypes.c_uint32
    ]

    try:
        fd = os.open(card, os.O_RDWR | os.O_CLOEXEC)
    except OSError as exc:
        report("RESULT", "NO_DRM_NODE")
        report("ERROR", exc)
        return 0

    report("DRM_NODE", card)

    dev = gbm.gbm_create_device(fd)

    if not dev:
        report("RESULT", "GBM_DEVICE_FAIL")
        os.close(fd)
        return 0

    report("GBM_DEVICE", "ok")

    # Which formats does this GBM accept for a scanout+render surface? SDL
    # picks one of these and never says which, or why it was refused.
    width = int(os.environ.get("RGB30_W", "720"))
    height = int(os.environ.get("RGB30_H", "720"))

    for name, code in FORMATS:
        supported = gbm.gbm_device_is_format_supported(dev, code, SDL_USAGE)
        surface = gbm.gbm_surface_create(dev, width, height, code, SDL_USAGE)

        report(
            "FORMAT",
            f"{name} supported={bool(supported)} "
            f"surface={'ok' if surface else 'FAIL'}"
        )

    # Now the EGL half, in the order SDL does it.
    egl.eglGetDisplay.restype = ctypes.c_void_p
    egl.eglGetDisplay.argtypes = [ctypes.c_void_p]
    egl.eglInitialize.argtypes = [
        ctypes.c_void_p, ctypes.POINTER(ctypes.c_int),
        ctypes.POINTER(ctypes.c_int)
    ]
    egl.eglChooseConfig.argtypes = [
        ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.c_void_p,
        ctypes.c_int, ctypes.POINTER(ctypes.c_int)
    ]
    egl.eglGetConfigAttrib.argtypes = [
        ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int,
        ctypes.POINTER(ctypes.c_int)
    ]
    egl.eglQueryString.restype = ctypes.c_char_p
    egl.eglQueryString.argtypes = [ctypes.c_void_p, ctypes.c_int]

    # Which client extensions exist BEFORE any display - this is where
    # EGL_KHR_platform_gbm / EGL_EXT_platform_base would advertise themselves.
    client_ext = egl.eglQueryString(None, 0x3055)   # EGL_EXTENSIONS
    report(
        "EGL_CLIENT_EXT",
        client_ext.decode() if client_ext else "(none - EGL_EXT_client_extensions unsupported)"
    )

    # SDL only loads eglGetPlatformDisplay after deciding EGL is >= 1.5, and it
    # decides that by calling eglQueryString(EGL_NO_DISPLAY, EGL_VERSION).
    # Plenty of drivers answer only EGL_EXTENSIONS without a display and return
    # NULL here, which leaves SDL believing it is on EGL 0.0. Whether that
    # happens on this blob is the difference between SDL taking the platform
    # path that works and the legacy path that does not.
    no_display_version = egl.eglQueryString(None, 0x3054)   # EGL_VERSION
    report(
        "EGL_VERSION_NO_DISPLAY",
        no_display_version.decode() if no_display_version
        else "NULL - SDL would read this as EGL 0.0"
    )

    # SDL does not call eglGetDisplay first. KMSDRM asks for the GBM platform
    # via eglGetPlatformDisplay, falling back to the EXT form, and only then to
    # the legacy call. Try them in SDL's order so this probe fails where SDL
    # fails rather than somewhere SDL never goes.
    egl.eglGetProcAddress.restype = ctypes.c_void_p
    egl.eglGetProcAddress.argtypes = [ctypes.c_char_p]

    GetPlatformDisplay = ctypes.CFUNCTYPE(
        ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p
    )

    display = None
    how = None

    for name in (b"eglGetPlatformDisplay", b"eglGetPlatformDisplayEXT"):
        addr = egl.eglGetProcAddress(name)
        report("EGL_ENTRY", f"{name.decode()}={'present' if addr else 'MISSING'}")

        if not addr or display:
            continue

        try:
            fn = GetPlatformDisplay(addr)
            candidate = fn(EGL_PLATFORM_GBM_KHR, ctypes.c_void_p(dev), None)

            if candidate:
                display = candidate
                how = name.decode()
        except Exception as exc:
            report("EGL_ENTRY_ERROR", f"{name.decode()}: {exc!r}")

    if not display:
        legacy = egl.eglGetDisplay(ctypes.c_void_p(dev))
        report("EGL_LEGACY_getdisplay", "ok" if legacy else "EGL_NO_DISPLAY")

        if legacy:
            display = legacy
            how = "eglGetDisplay"

    if not display:
        # Last resort: does EGL come up at all on this device, ignoring GBM?
        default = egl.eglGetDisplay(ctypes.c_void_p(0))
        report("EGL_DEFAULT_DISPLAY", "ok" if default else "EGL_NO_DISPLAY")

        report("RESULT", "EGL_GET_DISPLAY_FAIL")
        report("EGL_ERROR", hex(egl.eglGetError()))
        os.close(fd)
        return 0

    report("EGL_DISPLAY_VIA", how)

    major = ctypes.c_int(0)
    minor = ctypes.c_int(0)

    if not egl.eglInitialize(
        ctypes.c_void_p(display),
        ctypes.byref(major),
        ctypes.byref(minor)
    ):
        report("RESULT", "EGL_INIT_FAIL")
        report("EGL_ERROR", hex(egl.eglGetError()))
        os.close(fd)
        return 0

    report("EGL_VERSION", f"{major.value}.{minor.value}")

    vendor = egl.eglQueryString(ctypes.c_void_p(display), 0x3053)
    report("EGL_VENDOR", vendor.decode() if vendor else "?")

    attribs = (ctypes.c_int * 13)(
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 0,
        EGL_NONE
    )

    configs = (ctypes.c_void_p * 32)()
    num = ctypes.c_int(0)

    if not egl.eglChooseConfig(
        ctypes.c_void_p(display), attribs, configs, 32, ctypes.byref(num)
    ):
        report("RESULT", "EGL_CHOOSE_CONFIG_FAIL")
        report("EGL_ERROR", hex(egl.eglGetError()))
        os.close(fd)
        return 0

    report("EGL_CONFIGS", num.value)

    # The native visual id is the fourcc SDL then hands to gbm_surface_create.
    # If EGL offers ids that GBM refuses for scanout, that mismatch is the bug,
    # and it is invisible from SDL's single error message.
    seen = []

    for i in range(min(num.value, 8)):
        vid = ctypes.c_int(0)

        if egl.eglGetConfigAttrib(
            ctypes.c_void_p(display), configs[i],
            EGL_NATIVE_VISUAL_ID, ctypes.byref(vid)
        ):
            raw = vid.value & 0xFFFFFFFF
            tag = "".join(
                chr((raw >> s) & 0xFF) for s in (0, 8, 16, 24)
            )
            usable = gbm.gbm_device_is_format_supported(dev, raw, SDL_USAGE)
            seen.append(f"{tag}({'ok' if usable else 'REFUSED'})")

    report("EGL_VISUALS", " ".join(seen) if seen else "none")

    # The step the earlier run stopped short of. Choosing a config and finding
    # its visual acceptable is not the same as EGL agreeing to make a surface
    # on a real gbm_surface, and that final call is the one SDL makes last. If
    # it fails here too, the wall is EGL's, not SDL's.
    egl.eglCreateWindowSurface.restype = ctypes.c_void_p
    egl.eglCreateWindowSurface.argtypes = [
        ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_int)
    ]

    made = False

    for i in range(min(num.value, 4)):
        vid = ctypes.c_int(0)

        if not egl.eglGetConfigAttrib(
            ctypes.c_void_p(display), configs[i],
            EGL_NATIVE_VISUAL_ID, ctypes.byref(vid)
        ):
            continue

        fmt = vid.value & 0xFFFFFFFF
        gs = gbm.gbm_surface_create(dev, width, height, fmt, SDL_USAGE)

        if not gs:
            report("SURFACE", f"config{i} gbm_surface_create FAILED")
            continue

        es = egl.eglCreateWindowSurface(
            ctypes.c_void_p(display), configs[i], ctypes.c_void_p(gs), None
        )

        if es:
            report("SURFACE", f"config{i} eglCreateWindowSurface ok")
            made = True
            break

        report(
            "SURFACE",
            f"config{i} eglCreateWindowSurface FAILED err={hex(egl.eglGetError())}"
        )

    report("FULL_CHAIN", "ok" if made else "FAILED")
    report("RESULT", "DONE")

    os.close(fd)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        report("RESULT", "PROBE_CRASH")
        report("ERROR", repr(exc))
        sys.exit(0)
