"""RetroArch udev and SDL joystick indices per code, and candidate configs from the guided steps.
Numbering as RetroArch v1.22.2 udev_joypad.c and SDL 2.28.5 / 2.32.0 linux/SDL_sysjoystick.c.
"""
import struct

from button_reader.names import EV_ABS, EV_KEY, HAT_FIRST, HAT_LAST, abs_name, key_name

KEY_UP = 103
KEY_DOWN = 108
BTN_MISC = 0x100
BTN_JOYSTICK = 0x120
KEY_MAX = 0x2FF
ABS_MISC = 0x28
ABS_MAX = 0x3F
RA_MAX_BUTTONS = 64
RA_MAX_AXES = 32

# (slot, RetroArch bind, SDL field). SDL fields are spruce's label-named form, as the cfgs'
# SDL_GAMECONTROLLER_MAP: a = right, b = bottom, x = top, y = left.
BINDS = [("BOTTOM", "b", "b"), ("RIGHT", "a", "a"), ("TOP", "x", "x"), ("LEFT", "y", "y"),
         ("L1", "l", "leftshoulder"), ("R1", "r", "rightshoulder"), ("L2", "l2", "lefttrigger"),
         ("R2", "r2", "righttrigger"), ("DPAD_UP", "up", "dpup"), ("DPAD_DOWN", "down", "dpdown"),
         ("DPAD_LEFT", "left", "dpleft"), ("DPAD_RIGHT", "right", "dpright"),
         ("SELECT", "select", "back"), ("START", "start", "start"), ("L3", "l3", "leftstick"),
         ("R3", "r3", "rightstick"), ("MENU", None, "guide")]
STICK_BINDS = [("LEFT_X", "l_x", "leftx"), ("LEFT_Y", "l_y", "lefty"),
               ("RIGHT_X", "r_x", "rightx"), ("RIGHT_Y", "r_y", "righty")]
SDL_ORDER = ["a", "b", "x", "y", "back", "guide", "start", "leftshoulder", "rightshoulder",
             "lefttrigger", "righttrigger", "leftstick", "rightstick", "dpup", "dpdown", "dpleft",
             "dpright", "leftx", "lefty", "rightx", "righty"]
HAT_MASK = {("y", -1): 1, ("x", 1): 2, ("y", 1): 4, ("x", -1): 8}


def ra_buttons(keys):
    keyset = set(keys)
    order = []
    for low, high in ((KEY_UP, KEY_DOWN + 1), (BTN_MISC, KEY_MAX), (0, KEY_UP), (KEY_DOWN + 1, BTN_MISC)):
        order += [c for c in range(low, high) if c in keyset]
    return {code: i for i, code in enumerate(order[:RA_MAX_BUTTONS])}


def ra_axes(axes):
    order = [a for a in range(ABS_MISC) if a in axes and not HAT_FIRST <= a <= HAT_LAST
             and axes[a]["max"] > axes[a]["min"]]
    return {code: i for i, code in enumerate(order[:RA_MAX_AXES])}


def sdl_buttons(keys):
    keyset = set(keys)
    order = [c for c in range(BTN_JOYSTICK, KEY_MAX) if c in keyset] + [c for c in range(BTN_JOYSTICK) if c in keyset]
    return {code: i for i, code in enumerate(order)}


def _digital_hat(x, y):
    if not x and not y:
        return False
    if all(i is None or (i["min"] == -1 and i["max"] == 1) for i in (x, y)):
        return True
    return all(i is None or not (i["fuzz"] or i["flat"] or i.get("res", 0)) for i in (x, y))


def sdl_hats(axes):
    """{hat abs code: SDL hat number} for the hat pairs SDL treats as digital."""
    hats = {}
    number = 0
    for code in range(HAT_FIRST, HAT_LAST + 1, 2):
        if _digital_hat(axes.get(code), axes.get(code + 1)):
            for c in (code, code + 1):
                if c in axes:
                    hats[c] = number
            number += 1
    return hats


def sdl_axes(axes):
    hats = sdl_hats(axes)
    order = [a for a in range(ABS_MAX) if a in axes and a not in hats]
    return {code: i for i, code in enumerate(order)}


def crc16(data, crc=0):
    """SDL_crc16 (CRC-16/ARC): the name checksum SDL 2.26+ puts in a GUID."""
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def sdl_guid(ident, name, crc=0):
    """The GUID SDL builds for an evdev node; mappings carry it with a zero CRC."""
    bus, vendor, product, version = ident
    data = struct.pack("<HH", bus, crc)
    if vendor and product:
        data += struct.pack("<HHHHH", vendor, 0, product, 0, version) + b"\0\0"
    else:
        data += name.encode("utf-8")[:11].ljust(12, b"\0")
    return data.hex()


def numbering(node):
    """{"ra_buttons", "ra_axes", "sdl_buttons", "sdl_axes", "sdl_hats"} for one node."""
    return {"ra_buttons": ra_buttons(node.keys), "ra_axes": ra_axes(node.axes),
            "sdl_buttons": sdl_buttons(node.keys), "sdl_axes": sdl_axes(node.axes),
            "sdl_hats": sdl_hats(node.axes)}


def _hat_dir(code, direction):
    axis = "x" if (code - HAT_FIRST) % 2 == 0 else "y"
    return axis, {("x", -1): "left", ("x", 1): "right", ("y", -1): "up", ("y", 1): "down"}[(axis, direction)]


def _ra_value(control, num):
    """(bind suffix, value) for RetroArch, or None when it can't take this control."""
    etype, code, direction = control
    if etype == EV_KEY and code in num["ra_buttons"]:
        return "btn", str(num["ra_buttons"][code])
    if etype == EV_ABS and HAT_FIRST <= code <= HAT_LAST:
        return "btn", f"h{(code - HAT_FIRST) // 2}{_hat_dir(code, direction)[1]}"
    if etype == EV_ABS and code in num["ra_axes"]:
        return "axis", f"{'+' if direction > 0 else '-'}{num['ra_axes'][code]}"
    return None


def _sdl_value(control, num):
    etype, code, direction = control
    if etype == EV_KEY and code in num["sdl_buttons"]:
        return f"b{num['sdl_buttons'][code]}"
    if etype == EV_ABS and code in num["sdl_hats"]:
        return f"h{num['sdl_hats'][code]}.{HAT_MASK[(_hat_dir(code, direction)[0], direction)]}"
    if etype == EV_ABS and code in num["sdl_axes"]:
        return f"{'+' if direction > 0 else '-'}a{num['sdl_axes'][code]}" if HAT_FIRST <= code <= HAT_LAST \
            else f"{'' if direction > 0 else '-'}a{num['sdl_axes'][code]}"
    return None


def pad_node(answers, nodes):
    """The node most measured answers came from: the one the candidates describe."""
    counts = {}
    for short, _control in answers.values():
        counts[short] = counts.get(short, 0) + 1
    if not counts:
        return None
    best = max(counts, key=lambda s: (counts[s], -list(counts).index(s)))
    return next((n for n in nodes if n.short == best), None)


def candidates(answers, nodes):
    """(RetroArch autoconfig text, SDL_GAMECONTROLLER_MAP line, notes) from {role: (node, control)}."""
    node = pad_node(answers, nodes)
    if node is None:
        return None, None, ["no step was answered: no candidate configs"]
    num = numbering(node)
    notes = []
    ra = ["# Candidate RetroArch autoconfig from Button Reader's guided steps (by position).",
          "# Check it before use: RetroArch's udev driver matches it by input_device.",
          'input_driver = "udev"', f'input_device = "{node.name}"',
          f'input_vendor_id = "{node.ident[1]}"', f'input_product_id = "{node.ident[2]}"', ""]
    sdl = {}
    for slot, ra_bind, sdl_field in BINDS:
        answer = answers.get(slot)
        if not answer:
            continue
        short, control = answer
        if short != node.short:
            notes.append(f"{slot} answered on {short}, not {node.short}: left out of both")
            continue
        if control[0] == EV_KEY:
            what = key_name(control[1])
        else:
            what = f"{abs_name(control[1])} {'+' if control[2] > 0 else '-'}"
        ra_value = _ra_value(control, num)
        if ra_bind and ra_value:
            ra.append(f"# {slot.lower()}: {control[1]} {what}")
            ra.append(f'input_{ra_bind}_{ra_value[0]} = "{ra_value[1]}"')
        elif slot == "MENU" and ra_value:
            ra.append(f"# menu is {ra_value[0]} {ra_value[1]} ({control[1]} {what}); spruce's own watcher handles it")
        sdl_value = _sdl_value(control, num)
        if sdl_value:
            sdl[sdl_field] = sdl_value
    for role, ra_bind, sdl_field in STICK_BINDS:
        answer = answers.get(role)
        if not answer:
            continue
        short, (etype, code, direction) = answer
        if short != node.short or code not in num["ra_axes"]:
            notes.append(f"{role} answered on {short} axis {code}: left out")
            continue
        plus, minus = ("+", "-") if direction > 0 else ("-", "+")
        index = num["ra_axes"][code]
        ra.append(f"# {role.lower()}: {abs_name(code)}{' (reads negative right/down)' if direction < 0 else ''}")
        ra.append(f'input_{ra_bind}_plus_axis = "{plus}{index}"')
        ra.append(f'input_{ra_bind}_minus_axis = "{minus}{index}"')
        if code in num["sdl_axes"]:
            sdl[sdl_field] = f"a{num['sdl_axes'][code]}{'~' if direction < 0 else ''}"
    fields = ",".join(f"{k}:{sdl[k]}" for k in SDL_ORDER if k in sdl)
    line = f"{sdl_guid(node.ident, node.name)},{node.name},{fields},platform:Linux,"
    return "\n".join(ra) + "\n", line, notes
