"""The verbose diagnostic: a text report in reports/, plus candidate RetroArch / SDL files."""
import glob
import hashlib
import os
import time

from button_reader import VERSION, emulator_maps, features
from button_reader.names import EV_ABS, EV_KEY, HAT_FIRST, HAT_LAST, abs_name, face_print_text, key_name

ENV_PREFIXES = ("B_", "STICK_", "EVENT_PATH_", "DEVICE_NUM_ANALOG_STICKS", "SDL_GAMECONTROLLER",
                "PLATFORM", "PYUI_", "CONTROLLER_", "FN_KEY_", "SPRUCE_DEVICE_NAME", "DISPLAY_", "RUMBLE_",
                "LED_PATH", "DEVICE_HAS_", "WIFI_MODULE", "WIFI_ONBOARD_MODULE")


def _read(path, mode="r"):
    """A file's contents, or None. Text that isn't UTF-8 (the H700's debugfs gpio) reads with replacement marks."""
    try:
        with open(path, mode, **({} if "b" in mode else {"errors": "replace"})) as fh:
            return fh.read()
    except OSError:
        return None


def unique_path(folder, stem):
    n = 1
    while os.path.exists(os.path.join(folder, f"{stem}-{n}.txt")):
        n += 1
    return os.path.join(folder, f"{stem}-{n}")


class Report:
    def __init__(self, folder, platform):
        os.makedirs(folder, exist_ok=True)
        self.base = unique_path(folder, f"button-reader-{platform}")
        self.path = self.base + ".txt"
        self.fh = open(self.path, "w")
        self.synced = time.monotonic()

    def line(self, text=""):
        self.fh.write(text + "\n")
        self.fh.flush()
        if time.monotonic() - self.synced > 3:  # survive a power-off mid-run
            os.fsync(self.fh.fileno())
            self.synced = time.monotonic()

    def close(self):
        try:
            self.fh.flush()
            os.fsync(self.fh.fileno())
        finally:
            self.fh.close()

    def header(self, session):
        self.line(f"Button Reader {VERSION} report (verbose)")
        uptime = (_read("/proc/uptime") or "?").strip()
        self.line(f"date (device clock): {time.strftime('%Y-%m-%d %H:%M:%S')}   uptime: {uptime}")
        self.line(f"device: {session.manifest.name}   platform: {session.platform}   "
                  f"PyUI device: {session.device_desc}")
        self.line(session.manifest_text())
        self.line(f"controls: {session.controls_summary()}")
        for text in session.source_lines():
            self.line(f"source {text}")
        for slot, mine, theirs in session.manifest.cfg_differences(session.env):
            self.line(f"cfg differs: {slot}: the manifest says {mine}, the cfg {theirs}")
        self.line(f"face buttons: {face_print_text(session.manifest.face_print)} (the step prompts name both)")
        if session.switch is not None:
            position = session.switch.value if session.switch.readable else "none readable"
            self.line(f"Fn switch: {position} (spruce's device_get_switch_position)")
        if session.joystick is not None and session.joystick.pids:
            self.line("stick: spruce's joystickinput is in analog mode while the app is open (keyboard mode at exit)")
        model = (_read("/proc/device-tree/model", "rb") or b"?").rstrip(b"\0").decode("utf-8", "replace")
        self.line(f"model: {model}   kernel: {os.uname().release} {os.uname().machine}")
        for path in ["/sys/firmware/fdt"] + sorted(glob.glob("/boot/*.dtb*")):
            data = _read(path, "rb")
            if data:
                self.line(f"dtb: {path} {len(data)} B sha256 {hashlib.sha256(data).hexdigest()}")
        self.line()
        self.line("--- device features (sysfs, PyUI and the cfg, read once)")
        for label, text in features.detect(session.env, session.roots, session.nodes, session.pyui_device,
                                           session.pad.touch, session.spruce):
            self.line(f"{label}: {text}")
        self.line()
        self.line("--- platform cfg values PyUI's environment carries")
        for key in sorted(k for k in session.env if k.startswith(ENV_PREFIXES)):
            self.line(f"{key}={session.env[key]}")
        self.line()

    def inventory(self, session, full):
        """The nodes: one line each at the start, every capability at the end (with ranges seen)."""
        if full:
            self.line("--- input nodes in full (RA = RetroArch udev index, SDL = SDL Linux joystick index)")
        else:
            self.line("--- input nodes (in full at the end of the report)")
        for info in session.infos:
            self.node(session, info) if full else self.line(info.summary())
        for error in session.open_errors:
            self.line(error)
        self.line()

    def node(self, session, info):
        node = info.node
        names = session.names
        num = emulator_maps.numbering(node)
        self.line(info.summary())
        if node.uniq:
            self.line(f"    uniq: {node.uniq}")
        guid = emulator_maps.sdl_guid(node.ident, node.name)
        self.line(f"    SDL GUID for mappings: {guid}")
        for code in node.keys:
            control = (EV_KEY, code, 1)
            self.line(f"    key {names.describe(control)}; RA {num['ra_buttons'].get(code, '-')}, "
                      f"SDL b{num['sdl_buttons'].get(code, '-')}; {info.wiring_text(code, session.consumers)}")
        for axis, i in sorted(node.axes.items()):
            seen = session.pad.extremes.get((node.short, axis))
            role = names.stick_role(axis)
            pyui = [names.pyui.get((EV_ABS, axis, s)) for s in (-1, 1)]
            if role:
                what = f"stick {role[0]} {role[1]}{' (inverted)' if role[2] < 0 else ''}"
            else:
                what = ", ".join(f"{abs_name(axis)}{'-+'[k]} = PyUI {p}" for k, p in enumerate(pyui) if p) or "unmapped"
            sdl = (f"SDL hat {num['sdl_hats'][axis]}" if axis in num["sdl_hats"]
                   else f"SDL a{num['sdl_axes'].get(axis, '-')}")
            ra = f"hat {(axis - HAT_FIRST) // 2}" if HAT_FIRST <= axis <= HAT_LAST else num["ra_axes"].get(axis, "-")
            seen_text = f"{seen[0]}..{seen[1]}" if seen else "-"
            self.line(f"    abs {axis} {abs_name(axis)}: min {i['min']} max {i['max']} fuzz {i['fuzz']} "
                      f"flat {i['flat']} res {i.get('res', 0)} at start {i['value']}; seen {seen_text}; "
                      f"{what}; RA {ra}, {sdl}")
        for name, adc, channel in info.adc:
            self.line(f"    ADC input {name}: {adc} channel {channel}")

    def button_table(self, session):
        """One row per control a cfg or PyUI names: DT -> GPIO -> code -> PyUI -> cfg -> RA / SDL."""
        self.line("--- per button: slot | DT node and label -> GPIO | kernel code | PyUI | cfg | RA udev | SDL")
        names = session.names
        rows = sorted(set(names.slot) | set(names.pyui), key=lambda c: (c[0], c[1], c[2]))
        for control in rows:
            etype, code, direction = control
            holders = [i for i in session.infos if (code in i.node.keys if etype == EV_KEY else code in i.node.axes)]
            if not holders:
                what = key_name(code) if etype == EV_KEY else abs_name(code)
                self.line(f"{names.slot.get(control, '-'):10} | no node reports {what}"
                          f" | {code} | {names.pyui.get(control, '-')} | {names.cfg_var.get(control, '-')} | - | -")
                continue
            for info in holders:
                num = emulator_maps.numbering(info.node)
                if etype == EV_KEY:
                    wiring = info.wiring_text(code, session.consumers)
                    ra = num["ra_buttons"].get(code, "-")
                    sdl = f"b{num['sdl_buttons'].get(code, '-')}"
                    what = key_name(code)
                else:
                    wiring = "analog/hat axis (see the node's abs lines)"
                    ra = emulator_maps._ra_value(control, num)
                    ra = ra[1] if ra else "-"
                    sdl = emulator_maps._sdl_value(control, num) or "-"
                    what = f"{abs_name(code)} {'+' if direction > 0 else '-'}"
                self.line(f"{names.slot.get(control, '-'):10} | {wiring} | {info.node.short} {code} {what} | "
                          f"{names.pyui.get(control, '-')} | {names.cfg_var.get(control, '-')} | {ra} | {sdl}")
        self.line()

    def finish(self, session):
        self.line()
        self.line("--- steps (the cfg is by position: B_A right, B_B bottom, B_X top, B_Y left)")
        for result in session.step_results:
            self.line(f"{result['verdict']:9} {result['prompt']:46} expected {result['want']}; got {result['got']}")
        self.line()
        self.line("--- axis ranges seen")
        for (short, axis), (low, high) in sorted(session.pad.extremes.items()):
            self.line(f"{short} {abs_name(axis)}: {low}..{high}, last {session.pad.values.get((short, axis))}")
        self.line()
        self.inventory(session, full=True)
        self.button_table(session)
        ra, sdl, notes = emulator_maps.candidates(session.answers, session.nodes)
        self.line("--- candidate configs from the measured positions")
        for note in notes:
            self.line(f"note: {note}")
        if ra:
            ra_path = self.base + "-retroarch.cfg"
            sdl_path = self.base + "-sdl.txt"
            with open(ra_path, "w") as fh:
                fh.write(ra)
            with open(sdl_path, "w") as fh:
                fh.write(f"# spruce's label-named form (SDL_GAMECONTROLLER_MAP); export_sdl_gamecontroller_map "
                         f"positional swaps a/b and x/y\n{sdl}\n")
            self.line(f"RetroArch autoconfig: {os.path.basename(ra_path)}")
            for text in ra.splitlines():
                self.line(f"    {text}")
            self.line(f"SDL_GAMECONTROLLER_MAP ({os.path.basename(sdl_path)}):")
            self.line(f"    {sdl}")
        self.line()
        self.line("--- /proc/bus/input/devices")
        self.line((_read("/proc/bus/input/devices") or "unreadable").strip())
        gpio = _read("/sys/kernel/debug/gpio")
        self.line()
        self.line("--- /sys/kernel/debug/gpio" + ("" if gpio else ": not mounted or unreadable"))
        if gpio:
            self.line(gpio.strip())
