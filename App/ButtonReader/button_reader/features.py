"""What the device reports about itself beyond the buttons, read once (sysfs, PyUI, the cfg) for the info
pane and the report: display, panel, PyUI's scale, rumble, LEDs, RGB, Bluetooth, Wi-Fi, touch and the lid. Read-only.
"""
import glob
import os


def _read(path):
    try:
        with open(path, errors="replace") as fh:
            return fh.read().strip()
    except OSError:
        return None


def _call(obj, name):
    method = getattr(obj, name, None)
    if not callable(method):
        return None
    try:
        return method()
    except Exception:
        return None


def _names(pattern):
    return sorted(os.path.basename(p) for p in glob.glob(pattern))


def _listed(items, limit=4):
    if not items:
        return "none"
    return ", ".join(items[:limit]) + (f" +{len(items) - limit}" if len(items) > limit else "")


def _cfg(env, *keys):
    got = [f"{k}={env[k]}" for k in keys if env.get(k)]
    return "; cfg " + ", ".join(got) if got else ""


def _rfkill(sys, kind):
    """'unblocked' / 'soft-blocked' ... for each rfkill switch of this type."""
    out = []
    for path in sorted(glob.glob(f"{sys}/class/rfkill/rfkill*")):
        if _read(f"{path}/type") != kind:
            continue
        soft = _read(f"{path}/soft")
        hard = _read(f"{path}/hard")
        state = "hard-blocked" if hard == "1" else "soft-blocked" if soft == "1" else "unblocked"
        out.append(f"{_read(f'{path}/name') or os.path.basename(path)} {state}")
    return out


def display(env, sys, pyui_device):
    w = _call(pyui_device, "screen_width")
    h = _call(pyui_device, "screen_height")
    fb = _read(f"{sys}/class/graphics/fb0/virtual_size")
    bpp = _read(f"{sys}/class/graphics/fb0/bits_per_pixel")
    cfg = f"{env['DISPLAY_WIDTH']}x{env.get('DISPLAY_HEIGHT', '?')}" if env.get("DISPLAY_WIDTH") else "unset"
    text = f"cfg {cfg}, rotation {env.get('DISPLAY_ROTATION') or 0}"
    text += f"; PyUI {w}x{h}" if w and h else "; PyUI -"
    text += f"; fb0 {fb.replace(',', 'x')} at {bpp} bpp" if fb else "; no fb0"
    return text


def panel(env, sys):
    modes = (_read(f"{sys}/class/graphics/fb0/modes") or "").splitlines()
    drm = []
    for path in sorted(glob.glob(f"{sys}/class/drm/card*-*")):
        if _read(f"{path}/status") == "connected":
            first = (_read(f"{path}/modes") or "").splitlines()
            drm.append(f"{os.path.basename(path)} {first[0] if first else '?'}")
    lights = []
    for path in sorted(glob.glob(f"{sys}/class/backlight/*")):
        lights.append(f"{os.path.basename(path)} {_read(f'{path}/brightness')}/{_read(f'{path}/max_brightness')}")
    text = f"fb0 mode {modes[0]}" if modes else "fb0 mode -"
    text += f"; DRM {_listed(drm, 2)}" if drm else ""
    text += f"; backlight {_listed(lights, 2)}"
    return text + _cfg(env, "DISPLAY_ASPECT_RATIO", "DEVICE_BACKLIGHT_PATH")


def pyui_scale(env, pyui_device):
    scale = _call(pyui_device, "get_scale_factor")
    scaled = _call(pyui_device, "should_scale_screen")
    text = f"{scale if scale is not None else 'not reported'}"
    if scaled is not None:
        text += f" (scales the screen: {'yes' if scaled else 'no'})"
    if env.get("PYUI_DESKTOP_SCALE"):
        text += f"; desktop window x{env['PYUI_DESKTOP_SCALE']}"
    return text


def rumble(env, sys, nodes):
    found = []
    gpio = env.get("RUMBLE_GPIO", "")
    if gpio.isdigit():
        found.append(f"gpio{gpio} {'exported' if os.path.exists(f'{sys}/class/gpio/gpio{gpio}') else 'not exported'}")
    if os.path.isdir(f"{sys}/class/motor"):
        found.append("/sys/class/motor")
    ff = [f"{n.short} {n.name}" for n in nodes if (_read(f"{sys}/class/input/{n.short}/device/capabilities/ff")
                                                   or "0").strip("0 ")]
    if ff:
        found.append("force feedback on " + _listed(ff, 2))
    return (_listed(found) if found else "nothing detected") + _cfg(env, "RUMBLE_GPIO", "RUMBLE_PWMCHIP",
                                                                    "RUMBLE_SYSFS_PATH")


def leds(env, sys):
    names = _names(f"{sys}/class/leds/*")
    path = env.get("LED_PATH", "")
    text = _listed(names)
    if path:
        text += f"; cfg LED_PATH {'present' if os.path.exists(path) else 'missing'}"
    return text


def rgb(sys):
    found = []
    if os.path.isdir(f"{sys}/class/led_anim"):
        found.append("led_anim (TrimUI effects)")
    multi = [os.path.basename(os.path.dirname(p)) for p in sorted(glob.glob(f"{sys}/class/leds/*/multi_intensity"))]
    if multi:
        found.append("multicolor LEDs " + _listed(multi, 3))
    return _listed(found) if found else "none detected"


def bluetooth(sys, spruce=None):
    """spruce's answer first (the radio may be off, so no hci shows), then the adapter and rfkill seen now."""
    hci = _names(f"{sys}/class/bluetooth/hci*")
    kill = _rfkill(sys, "bluetooth")
    supported = spruce.get("bluetooth") if spruce is not None else None
    if supported == "0":
        text = "not on this board (spruce)"
    elif hci:
        text = f"adapter {_listed(hci)}" + ("; on this board (spruce)" if supported == "1" else "")
    elif supported == "1":
        text = "on this board (spruce); radio off: no adapter until Bluetooth is turned on"
    else:
        text = "no adapter"
    return text + (f"; rfkill {_listed(kill, 2)}" if kill else "")


def wifi(env, sys):
    nets = []
    for path in sorted(glob.glob(f"{sys}/class/net/wlan*")):
        nets.append(f"{os.path.basename(path)} {_read(f'{path}/operstate') or '?'}")
    kill = _rfkill(sys, "wlan")
    text = f"{_listed(nets)}" if nets else "no wlan interface"
    text += f"; rfkill {_listed(kill, 2)}" if kill else ""
    return text + _cfg(env, "WIFI_ONBOARD_MODULE", "WIFI_MODULE", "WIFI_USB_IDS")


def touch(env, nodes, touch_shorts):
    found = [f"{n.short} {n.name}" for n in nodes if n.short in touch_shorts]
    text = f"touchscreen {_listed(found, 2)}" if found else "no touchscreen node"
    return text + _cfg(env, "DEVICE_HAS_TOUCHSCREEN", "EVENT_PATH_TOUCH")


def lid(sys, nodes):
    """A hall-sensor node or one declaring SW_LID, and the sensor's sysfs reading where its driver gives one."""
    found = []
    for n in nodes:
        sw = (_read(f"{sys}/class/input/{n.short}/device/capabilities/sw") or "0").split()
        if "hall" in n.name.lower() or (sw and int(sw[-1], 16) & 1):
            found.append(f"{n.short} {n.name}")
    for path in sorted(glob.glob(f"{sys}/devices/platform/*hall*/hallvalue")):
        found.append(f"{os.path.basename(os.path.dirname(path))} reads {_read(path)}")
    return _listed(found, 3) if found else "none detected"


def detect(env, roots, nodes, pyui_device=None, touch_shorts=(), spruce=None):
    """[(label, text)], one row per feature."""
    sys = roots.sys
    return [("Display", display(env, sys, pyui_device)), ("Panel", panel(env, sys)),
            ("PyUI scale", pyui_scale(env, pyui_device)), ("Rumble", rumble(env, sys, nodes)),
            ("LEDs", leds(env, sys)), ("RGB", rgb(sys)), ("Bluetooth", bluetooth(sys, spruce)),
            ("Wi-Fi", wifi(env, sys)), ("Touch", touch(env, nodes, touch_shorts)), ("Lid", lid(sys, nodes))]
