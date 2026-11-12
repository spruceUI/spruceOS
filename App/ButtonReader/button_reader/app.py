"""Button Reader in PyUI's process: start screen, guided steps (full diagnostic), live picture.
It never calls Controller.get_input(), so PyUI's game switcher, hotkeys and screensaver stay out.
"""
import logging
import math
import os
import select
import time

from button_reader import VERSION, evdev, features, hardware, manifest, picture
from button_reader.fn_switch import FnSwitch
from button_reader.joystick_input import JoystickInput
from button_reader.spruce_query import SpruceQuery
from button_reader.manifest import SLOT_VARS
from button_reader.names import ABSENT, EV_ABS, EV_KEY, EV_SW, HAT_FIRST, HAT_LAST, KEY_POWER, SLOTS, STICKS, SW_NAMES
from button_reader.names import Names, abs_name, cfg_spec, face_print_text, face_prompt, parse_spec, pyui_tables, sign
from button_reader.names import spec_control, stick_axis

EXIT_HOLD = 10.0
COUNTDOWN_AFTER = 3.0
START_WINDOW = 3.0
STEP_TIMEOUT = 7.0  # a guided step skips itself after this long without an answer
SETTLE_MAX = 3.0
SETTLE_QUIET = 0.1  # at rest this long before the next step asks: outlasts a switch's release bounce
RELEASE_WAIT = 3.0
RESCAN_SECONDS = 2.0
REDRAW_SECONDS = 0.25
MIN_FRAME = 1 / 30.0
RECENT_LINES = 2  # last presses listed under the picture, between the device's name and the status line
INFO_HOLD = 5.0  # L1 + R1 held this long in the picture opens the device info
INFO_MIRROR = 0.1  # a press this soon after one the info pane acted on is its copy (the A30's joypad mirror)
INFO_PAGE = 5  # rows D-pad left/right scroll the info pane
HAT_DPAD = {(17, -1): "DPAD_UP", (17, 1): "DPAD_DOWN", (16, -1): "DPAD_LEFT", (16, 1): "DPAD_RIGHT"}
KEY_DPAD = {103: "DPAD_UP", 108: "DPAD_DOWN", 105: "DPAD_LEFT", 106: "DPAD_RIGHT"}
INFO_SCROLL = {"DPAD_UP": -1, "DPAD_DOWN": 1, "DPAD_LEFT": -INFO_PAGE, "DPAD_RIGHT": INFO_PAGE}
APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXIT_HINT = "Exit: hold a button 10 s, or Select+Start"

# A face step's prompt (None here) is names.face_prompt: FACE_SOUTH/B, or FACE_SOUTH/A on an Xbox print.
KEY_STEPS = [("BOTTOM", None), ("RIGHT", None), ("TOP", None), ("LEFT", None),
             ("DPAD_UP", "Press D-pad UP"), ("DPAD_DOWN", "Press D-pad DOWN"),
             ("DPAD_LEFT", "Press D-pad LEFT"), ("DPAD_RIGHT", "Press D-pad RIGHT"),
             ("L1", "Press L1 (upper left shoulder)"), ("R1", "Press R1 (upper right shoulder)"),
             ("L2", "Press L2 (lower left shoulder)"), ("R2", "Press R2 (lower right shoulder)"),
             ("SELECT", "Press SELECT"), ("START", "Press START"), ("L3", "Click the LEFT stick in (L3)"),
             ("R3", "Click the RIGHT stick in (R3)"), ("MENU", "Tap MENU"), ("HOME", "Press HOME"),
             ("FN_LEFT", "Press the left Fn key"), ("FN_RIGHT", "Press the right Fn key"),
             ("VOL_UP", "Press VOL+"), ("VOL_DOWN", "Press VOL-")]
FN_SLOTS = ("FN_LEFT", "FN_RIGHT")
STICK_CLICKS = {"L3": 1, "R3": 2}  # the sticks a device needs for each click step
STICK_STEPS = [("LEFT_X", "LEFT", "x", "Push the LEFT stick fully RIGHT, then let go"),
               ("LEFT_Y", "LEFT", "y", "Push the LEFT stick fully DOWN, then let go"),
               ("RIGHT_X", "RIGHT", "x", "Push the RIGHT stick fully RIGHT, then let go"),
               ("RIGHT_Y", "RIGHT", "y", "Push the RIGHT stick fully DOWN, then let go")]


class Pad:
    """Held controls, axis values and the extremes seen, across every node."""

    def __init__(self, names):
        self.names = names
        self.values = {}
        self.extremes = {}
        self.info = {}
        self.pressed = {}
        self.push = {}  # (short, axis) -> directions that count as a press (triggers)
        self.touch = set()  # nodes with multitouch axes: their ABS_X/Y are a touchscreen
        self.rest = {}  # (short, axis) -> value when opened: an unmapped trigger rests off-centre

    def add_node(self, node):
        if 53 in node.axes:
            self.touch.add(node.short)
        for axis, info in node.axes.items():
            key = (node.short, axis)
            self.values[key] = self.rest[key] = info["value"]
            self.extremes.setdefault(key, [info["value"], info["value"]])
            self.info[key] = info
            known = {c[2] for c in list(self.names.slot) + list(self.names.pyui) if c[0] == EV_ABS and c[1] == axis}
            if not known:  # an unmapped one-sided axis: pressed away from where it rests
                mid = (info["min"] + info["max"]) / 2.0
                known = {1 if info["value"] <= mid else -1}
            self.push[key] = known

    def kind(self, short, axis):
        if HAT_FIRST <= axis <= HAT_LAST:
            return "hat"
        if axis >= 0x28 or short in self.touch:
            return "other"  # ABS_MISC and touchscreens
        if self.names.stick_role(axis):
            return "stick"
        if any(c[0] == EV_ABS and c[1] == axis for c in list(self.names.slot) + list(self.names.pyui)):
            return "trigger"
        info = self.info.get((short, axis))
        if info and info["min"] >= 0 and info["max"] > info["min"]:
            return "trigger"
        return "stick"

    def deflection(self, short, axis):
        info = self.info.get((short, axis))
        if not info or info["max"] - info["min"] < 2:
            return 0.0
        mid = (info["max"] + info["min"]) / 2.0
        half = (info["max"] - info["min"]) / 2.0
        return (self.values.get((short, axis), mid) - mid) / half

    def moved(self, short, axis):
        """Like deflection, but from where the axis rested when the app opened it."""
        info = self.info.get((short, axis))
        if not info or info["max"] - info["min"] < 2:
            return 0.0
        rest = self.rest.get((short, axis), (info["max"] + info["min"]) / 2.0)
        return (self.values.get((short, axis), rest) - rest) / ((info["max"] - info["min"]) / 2.0)

    def _active(self, short, axis, direction, kind):
        if kind == "hat":
            info = self.info.get((short, axis)) or {"min": -1, "max": 1}
            if info["max"] - info["min"] <= 2:
                return self.values.get((short, axis), 0) * direction > 0
            return self.deflection(short, axis) * direction > 0.5
        return direction in self.push.get((short, axis), ()) and self.deflection(short, axis) * direction > 0

    def feed(self, node, etype, code, value, now):
        """Update the state; returns [(kind, item)] changes: down/up (short, control), axis, switch."""
        short = node.short
        if etype == EV_KEY:
            key = (short, (EV_KEY, code, 1))
            if value == 1 and key not in self.pressed:
                self.pressed[key] = now
                return [("down", key)]
            if value == 0 and key in self.pressed:
                del self.pressed[key]
                return [("up", key)]
            return []
        if etype == EV_ABS:
            axis = (short, code)
            self.values[axis] = value
            low_high = self.extremes.setdefault(axis, [value, value])
            low_high[0] = min(low_high[0], value)
            low_high[1] = max(low_high[1], value)
            kind = self.kind(short, code)
            if kind not in ("hat", "trigger"):
                return [("axis", axis)]
            changes = []
            for direction in (-1, 1):
                key = (short, (EV_ABS, code, direction))
                active = self._active(short, code, direction, kind)
                if active and key not in self.pressed:
                    self.pressed[key] = now
                    changes.append(("down", key))
                elif not active and key in self.pressed:
                    del self.pressed[key]
                    changes.append(("up", key))
            return changes
        if etype == EV_SW:
            return [("switch", (short, code, value))]
        return []


class Session:
    def __init__(self, device=None, controller_interface=None, log=None, screen=None, env=None,
                 nodes=None, roots=None, report_dir=None, clock=time.monotonic, desktop=None, switch=None,
                 joystick=None, devices_dir=None, spruce=None):
        self.env = dict(os.environ if env is None else env)
        self.desktop = desktop
        self.switch = switch
        self.joystick = joystick
        self.spruce = spruce  # spruce's own answers (Bluetooth), asked once when first needed
        if desktop is not None:
            from button_reader.desktop_keys import ENV
            for key, value in ENV.items():
                self.env.setdefault(key, value)
        controls, sticks = pyui_tables(controller_interface, device)
        self.manifest = manifest.load(self.env, devices_dir)
        self.names = Names(self.env, controls, sticks, self.manifest)
        self.platform = self.env.get("PLATFORM") or "unknown"
        self.pyui_device = device
        aliases = ""
        try:
            aliases = ", ".join(device.get_device_names())
        except Exception:
            pass
        self.device_desc = type(device).__name__ if device is not None else "none"
        if aliases:
            self.device_desc += f" ({aliases})"
        self.log = log or logging.getLogger("ButtonReader")
        self.roots = roots or hardware.Roots()
        self.clock = clock
        self.screen = screen
        self.report_dir = report_dir or os.path.join(APP_DIR, "reports")
        self.open_errors = []
        if nodes is None:
            nodes = evdev.open_nodes(evdev.event_paths(self.roots.dev + "/input"), self.roots.sys, self.open_errors)
        self.nodes = list(nodes) + ([desktop] if desktop is not None else [])
        self.pad = Pad(self.names)
        for node in self.nodes:
            self.pad.add_node(node)
        self.infos, self.consumers, self.dt = hardware.inventory(self.nodes, self.roots)
        pad_paths = [getattr(controller_interface, "event_path", None), self.env.get("EVENT_PATH_READ_INPUTS_SPRUCE")]
        self.pad_paths = {os.path.realpath(p) for p in pad_paths if p and os.path.exists(p)}
        self.exit_hold = EXIT_HOLD
        self.countdown_after = COUNTDOWN_AFTER
        self.start_window = START_WINDOW
        self.step_timeout = STEP_TIMEOUT
        self.settle_max = SETTLE_MAX
        self.release_wait = RELEASE_WAIT
        self.settle_quiet = SETTLE_QUIET
        self.rest_since = None
        self.started = self.clock()
        self.mode = "start"
        self.mode_since = self.started
        self.verbose = False
        self.report = None
        self.report_path = None
        self.steps = []
        self.step_i = 0
        self.phase = "settle"
        self.phase_since = self.started
        self.step_results = []
        self.answers = {}
        self.last_record = None
        self.recent = []
        self.logged_axis = {}
        self._ranked = []
        self.failed = set()
        self.expect_from = {}
        self.info_hold = INFO_HOLD
        self.info_since = None  # when L1 + R1 began to be held together in the picture
        self.info_open = False
        self.info_lines = []
        self.info_scroll = 0
        self.info_max = None  # the last row the pane can scroll to, as last drawn
        self.info_acted = -1.0  # when the pane last scrolled or opened: mirrored copies of that press are skipped
        self.hold_floor = self.started  # the exit hold counts from here, so the info chord never exits
        self.done = False
        self.exit_reason = None
        self.dirty = True

    # --- logging

    def log_inventory(self):
        m = self.manifest
        self.log.info(f"Button Reader {VERSION}: {len(self.nodes)} input nodes on {m.name} ({self.platform}, "
                      f"{self.device_desc}), {face_print_text(m.face_print)}")
        self.log.info(f"Button Reader: {self.manifest_text()}")
        for text in self.source_lines():
            self.log.info(f"Button Reader:   {text}")
        for slot, mine, theirs in m.cfg_differences(self.env):
            self.log.info(f"Button Reader:   {slot}: the manifest says {mine}, the cfg {theirs}")
        for info in self.infos:
            node = info.node
            self.log.info(f"Button Reader: {info.summary()}")
            known = [c for c in node.keys if (EV_KEY, c, 1) in self.names.slot or (EV_KEY, c, 1) in self.names.pyui
                     or c in info.wiring or c in (114, 115, KEY_POWER)]
            for code in known:
                self.log.info(f"Button Reader:   {node.short} key {self.names.describe((EV_KEY, code, 1))}; "
                              f"{info.wiring_text(code, self.consumers)}")
            rest = [c for c in node.keys if c not in known]
            if rest:
                self.log.info(f"Button Reader:   {node.short} {len(rest)} other key codes: "
                              f"{' '.join(map(str, rest[:40]))}{' ...' if len(rest) > 40 else ''}")
            for axis, i in sorted(node.axes.items()):
                self.log.info(f"Button Reader:   {node.short} abs {axis} {abs_name(axis)} {i['min']}..{i['max']} "
                              f"fuzz {i['fuzz']} flat {i['flat']} now {i['value']}")
            for name, adc, channel in info.adc:
                self.log.info(f"Button Reader:   {node.short} ADC input {name}: {adc} channel {channel}")
        for error in self.open_errors:
            self.log.info(f"Button Reader: {error}")

    def manifest_text(self):
        m = self.manifest
        if m.known:
            models = ", ".join(m.data.get("models", []))
            return (f"manifest devices/{os.path.basename(m.path)}: {m.data.get('name')} ({models}); "
                    f"this unit: {m.model or 'model not told'}")
        return f"no manifest for {self.platform}: rules from the cfg" + (f" ({m.error})" if m.error else "")

    def source_lines(self):
        """Each manifest source, what stands for it here (the node(s) matching its name, the daemon, the GPIO) and
        the controls it feeds."""
        m = self.manifest
        if not m.known:
            return []
        out = []
        for sid, src in m.sources.items():
            kind = src.get("kind", "?")
            if m.node_names(sid):
                found = [n.short for n in self.nodes if m.matches(sid, n.name)]
                text = f"{sid} ({kind}) {m.node_names(sid)[0]}: {', '.join(found) if found else 'NOT FOUND'}"
            elif kind == "uart":
                pids = []
                if self.joystick is not None and src.get("fed_by") == "joystickinput":
                    try:
                        pids = self.joystick.find()
                    except OSError:
                        pass
                seen = f"pid {', '.join(map(str, pids))}" if pids else "not running"
                text = f"{sid} (uart) {src.get('device', '?')} via {src.get('fed_by', '?')}: {seen}"
            elif kind == "gpio":
                sw = self.switch
                if sw is not None and sw.readable:
                    seen = f"reads {sw.value}"
                else:  # None: the first read (a short sh run) hasn't come back yet
                    seen = "not read yet" if sw is not None and sw.readable is None else "not readable"
                text = f"{sid} (gpio) {src.get('device', '?')}: {seen}"
            else:
                text = f"{sid} ({kind})"
            out.append(f"{text}; feeds {m.feeds(sid)}")
        others = [f"{n.short} {n.name}" for n in self.nodes if not any(m.matches(sid, n.name) for sid in m.sources)]
        if others:
            out.append("not in the manifest: " + ", ".join(others))
        return out

    def source_note(self, role, short):
        """' (not from pad TRIMUI Player1)' when a press arrived on another node than the manifest's source."""
        sid, src = self.manifest.source_of(role)
        node = next((n for n in self.nodes if n.short == short), None)
        if not src or node is None or not self.manifest.node_names(sid) or self.manifest.matches(sid, node.name):
            return ""
        return f" (not from its source {sid}: {src.get('node')})"

    def controls_summary(self):
        m = self.manifest

        def yes(slot):
            has = m.has(slot)
            return "yes" if has else "no" if has is False else "?"
        clicks = [s for s in ("L3", "R3") if m.has(s) and m.control(s).get("label") != "Fn"]
        fn_keys = [s for s in ("L3", "R3") if m.control(s).get("label") == "Fn"] + [s for s in FN_SLOTS if m.has(s)]
        return (f"sticks {self.stick_count()} ({'click ' + '/'.join(clicks) if clicks else 'no clicks'}), "
                f"Home {yes('HOME')}, volume {yes('VOL_UP')}, Fn keys {'/'.join(fn_keys) or 'no'}, "
                f"Fn switch {yes('FN_SWITCH')}, lid {yes('LID')}, {m.face_print} print")

    def device_info(self):
        """The info pane: [(text, color)], what the manifest says and what this unit shows."""
        m = self.manifest
        rows = [(f"{m.name} ({self.platform})", picture.TEXT)]
        if m.known:
            d = m.data
            rows.append((" | ".join(str(d.get(k)) for k in ("brand", "soc", "base", "arch") if d.get(k)), picture.GRAY))
        rows.append((self.manifest_text(), picture.GRAY))
        rows.append(("Controls: " + self.controls_summary(), picture.TEXT))
        for text in self.source_lines():
            rows.append((f"Source {text}", picture.WARN if "NOT FOUND" in text else picture.GRAY))
        if not m.known:
            rows.append(("Input nodes: " + ", ".join(f"{n.short} {n.name}" for n in self.nodes), picture.GRAY))
        diffs = m.cfg_differences(self.env)
        if diffs:
            rows.append((f"cfg differs from the manifest on {', '.join(d[0] for d in diffs)}", picture.WARN))
        for label, text in features.detect(self.env, self.roots, self.nodes, self.pyui_device, self.pad.touch,
                                           self.spruce):
            rows.append((f"{label}: {text}", picture.TEXT))
        return rows

    def t(self):
        return self.clock() - self.started

    def event_line(self, text):
        if self.report:
            self.report.line(f"{self.t():9.3f} {text}")

    # --- input

    def is_power(self, control):
        return control == (EV_KEY, KEY_POWER, 1) or self.names.slot.get(control) == "POWER"

    def on_event(self, node, etype, code, value, now):
        if etype == EV_ABS and self.report:
            info = self.pad.info.get((node.short, code)) or {"min": 0, "max": 8}
            step = max((info["max"] - info["min"]) / 8.0, 1)
            logged = self.logged_axis.get((node.short, code), info.get("value", 0))
            if HAT_FIRST <= code <= HAT_LAST or abs(value - logged) >= step:
                self.logged_axis[(node.short, code)] = value
                self.event_line(f"{node.short} ABS {abs_name(code)} {value}")
        for kind, item in self.pad.feed(node, etype, code, value, now):
            self.dirty = True
            if kind in ("down", "up"):
                short, control = item
                text = f"{short} {kind:4} {self.names.describe(control)}"
                self.log.info(f"Button Reader: {text}")
                self.event_line(text)
                if kind == "down":
                    self.recent = ([text] + self.recent)[:RECENT_LINES]
                    self.on_press(short, control, now)
            elif kind == "switch":
                text = f"{item[0]} switch {SW_NAMES.get(item[1], item[1])} = {item[2]}"
                self.log.info(f"Button Reader: {text}")
                self.event_line(text)

    def on_press(self, short, control, now):
        if self.info_open:
            if now - self.info_acted >= INFO_MIRROR:
                step = self.info_step(control)
                if step:
                    last = self.info_max if self.info_max is not None else self.info_scroll + abs(step)
                    self.info_scroll = max(0, min(self.info_scroll + step, last))
                    self.info_acted = now
                elif not self.is_power(control):
                    self.info_open = False
                    self.event_line("device info closed")
                self.dirty = True
        elif self.mode == "start" and not self.is_power(control):
            self.start_verbose(now)
        elif self.mode == "steps" and self.phase == "ask" and self.steps[self.step_i][0] == "key" \
                and not self.is_power(control):
            self.record((short, control), now)
        if self.mode != "leaving" and self.chord_down():
            self.withdraw_chord_answer(now)
            self.begin_exit("Select + Start", now)

    def withdraw_chord_answer(self, now):
        """The chord's first key may have just answered a step: that answer was the exit, not a test."""
        last = self.last_record
        chord = set(self.names.controls_of("SELECT") + self.names.controls_of("START"))
        if not last or now - last[0] > 0.6 or last[2] not in chord:
            return
        _t, role, _control, previous = last
        self.step_results.pop()
        if previous is None:
            self.answers.pop(role, None)
        else:
            self.answers[role] = previous
        self.step_i -= 1
        self.last_record = None
        self.event_line(f"step {self.step_i + 1} answer withdrawn: it began the Select + Start exit")

    def chord_down(self):
        held = {c for _s, c in self.pad.pressed}
        select_controls = self.names.controls_of("SELECT")
        start_controls = self.names.controls_of("START")
        return bool(select_controls and start_controls and held & set(select_controls) and held & set(start_controls))

    def stick_count(self):
        """The manifest's sticks; without one, the cfg's count or the sticks whose axes the nodes report."""
        count = self.manifest.stick_count()
        if count is None:
            count = sum(1 for s in ("LEFT", "RIGHT") if any(self.stick_axes(s).values()))
        return count

    def expected(self, slot):
        """The control a step expects: the cfg's code, else the manifest's (the Minis' cfg holds placeholders)."""
        spec = cfg_spec(SLOT_VARS[slot], self.env)
        self.expect_from[slot] = "cfg"
        if spec in (None, ABSENT):
            spec = self.manifest.code(slot)
            self.expect_from[slot] = "manifest" if spec else None
        return spec_control(spec)

    def stick_axes(self, stick):
        """{"x": (short, axis, sign), "y": ...} for one stick, from the cfg/PyUI or the default axes."""
        out = {"x": None, "y": None}
        has = self.manifest.has(f"{stick}_STICK")
        if has is False:
            return out  # a pad that declares axes the device lacks (the A30's RX/RY) draws nothing for them
        info = self.names.sticks.get(stick)
        defaults = {s: (dx, dy) for s, _vx, _vy, dx, dy in STICKS}[stick]
        for k, axis in enumerate(("x", "y")):
            want = info[axis] if info and info[axis] else None
            if want is None and info is None:  # the stick exists, or nothing says it doesn't
                want = (defaults[k], 1)
            if want is None:
                continue
            for node in self.pad_first():
                ai = node.axes.get(want[0])
                if ai and (info or ai["min"] < 0 < ai["max"]) and self.pad.kind(node.short, want[0]) == "stick":
                    out[axis] = (node.short, want[0], want[1])
                    break
        return out

    def pad_first(self):
        """Nodes with PyUI's pad (or the cfg's input node) first, then gamepad-like ones."""
        if len(self._ranked) != len(self.nodes):
            def rank(node):
                real = os.path.realpath(node.path) if os.path.exists(node.path) else node.path
                if real in self.pad_paths:
                    return 0
                return 1 if any(304 <= k <= 318 or 544 <= k <= 547 for k in node.keys) else 2
            self._ranked = sorted(self.nodes, key=rank)
        return self._ranked

    def at_rest(self):
        if self.pad.pressed:
            return False
        return all(abs(self.pad.moved(s, a)) < 0.25 for (s, a) in self.pad.info if self.pad.kind(s, a) == "stick")

    # --- verbose mode

    def start_verbose(self, now):
        from button_reader.report import Report
        self.verbose = True
        if self.switch is not None:
            self.switch.wait_first(2.0)  # the header and the steps need to know whether there is one
        try:
            self.report = Report(self.report_dir, self.platform)
            self.report_path = self.report.path
            self.report.header(self)
            self.report.inventory(self, full=False)
            self.report.line("--- events (seconds since start)")
        except OSError as error:
            self.log.warning(f"Button Reader: no report ({error}); the steps still run")
            self.report = None
        m = self.manifest
        sticks = self.stick_count()
        names = self.names
        steps = []
        for slot, prompt in KEY_STEPS:
            has = m.has(slot)
            if has is False:
                continue
            if not m.known:
                # The cfg's rules. A stick click needs its stick (the Minis have none), but the Brick's Fn keys send
                # L3/R3. Virtual pads (the A30's joypad, trimui_inputd) declare 317/318 whatever the hardware has.
                if has is None and slot in ("HOME",) + FN_SLOTS and not names.controls_of(slot):
                    continue
                if sticks < STICK_CLICKS.get(slot, 0):
                    side = self.fn_key_side(slot)
                    if side is None:
                        continue
                    prompt = f"Press the {side} Fn key ({slot})"
            prompt = m.control(slot).get("prompt") or prompt or face_prompt(slot, m.face_print)
            steps.append(("key", slot, prompt, SLOT_VARS[slot], self.expected(slot)))
        for role, stick, axis, prompt in STICK_STEPS[:2 * min(sticks, 2)]:
            var = dict((s, (vx, vy)) for s, vx, vy, _dx, _dy in STICKS)[stick][0 if axis == "x" else 1]
            expected = stick_axis(cfg_spec(var, self.env))
            self.expect_from[role] = "cfg"
            over = m.over_cfg(f"{stick}_STICK")
            if over and stick_axis(parse_spec(over.get(axis))):  # measured axes win over the cfg's
                expected = stick_axis(parse_spec(over.get(axis)))
                self.expect_from[role] = "manifest"
            elif expected is None:
                expected = stick_axis(parse_spec(m.control(f"{stick}_STICK").get(axis)))
                self.expect_from[role] = "manifest" if expected else None
            steps.append(("stick", role, prompt, var, expected))
        if self.switch is not None and self.switch.readable and m.has("FN_SWITCH") is not False:
            steps.append(("switch", "FN_SWITCH", "Flip the Fn switch, then back (its action runs)",
                          "device_get_switch_position", None))
        self.steps = steps
        self.step_i = 0
        self.mode = "steps"
        self.mode_since = now
        self.phase = "settle"
        self.phase_since = now
        self.log.info(f"Button Reader: full diagnostic, {len(steps)} guided steps, report {self.report_path}")
        if not steps:
            self.mode = "picture"

    def record(self, answer, now):
        kind, role, prompt, var, expected = self.steps[self.step_i]
        if kind == "key":
            if expected:
                want = self.names.describe(expected)
                if self.expect_from.get(role) == "manifest":
                    want += " (manifest)"
            elif self.manifest.known and self.manifest.has(role):
                want = f"no code known (manifest: {self.manifest.control(role).get('from', '?')})"
            elif cfg_spec(var, self.env) == ABSENT:
                want = "nothing (cfg: DOESNT_EXIST)"
            else:
                want = "nothing (cfg unset)"
            got = f"{answer[0]} {self.names.describe(answer[1])}" if answer else "no input"
            if answer:
                got += self.source_note(role, answer[0])
            same = bool(answer) and answer[1] == expected
        elif kind == "switch":
            want = "a flip"
            got = f"{answer[1][0]} -> {answer[1][1]}" if answer else "no flip"
            same = bool(answer)
        else:
            want = f"{abs_name(expected[0])} {'+' if expected[1] > 0 else '-'}" if expected else "nothing (cfg unset)"
            if expected and self.expect_from.get(role) == "manifest":
                want += " (manifest)"
            got = (f"{answer[0]} {abs_name(answer[1][1])} {'+' if answer[1][2] > 0 else '-'}" if answer else "no input")
            same = bool(answer) and (answer[1][1], answer[1][2]) == tuple(expected or ())
        if not answer:
            verdict = "NO INPUT"
        elif kind == "switch":
            verdict = "OK"
        elif expected is None:
            verdict = "RECORDED"
        else:
            verdict = "OK" if same else "DIFFERENT"
        self.last_record = (now, role, answer[1] if answer else None, self.answers.get(role))
        if answer and kind != "switch":
            self.answers[role] = answer
        if answer and kind == "key" and expected is None and self.manifest.known and self.manifest.has(role):
            self.names.slot.setdefault(answer[1], role)  # a control the manifest lists without a code: lit from now
        if kind == "stick" or expected is None:
            want += f" ({var})"  # a key's description already names its cfg variable
        self.step_results.append({"prompt": prompt, "var": var, "want": want, "got": got, "verdict": verdict})
        self.event_line(f"step {self.step_i + 1} {verdict}: {prompt}: expected {want}, got {got}")
        self.log.info(f"Button Reader: step {verdict}: {prompt}: expected {want}, got {got}")
        self.step_i += 1
        self.phase = "settle"
        self.phase_since = now
        self.dirty = True
        if self.step_i >= len(self.steps):
            self.mode = "picture"
            self.mode_since = now

    def tick_steps(self, now):
        if self.phase == "settle":
            if not self.at_rest():
                self.rest_since = None
            elif self.rest_since is None:
                self.rest_since = now
            quiet = self.rest_since is not None and now - self.rest_since >= self.settle_quiet
            if quiet or now - self.phase_since > self.settle_max:
                self.phase = "ask"
                self.phase_since = now
                self.dirty = True
                self.rest_since = None
                self.event_line(f"step {self.step_i + 1}: {self.steps[self.step_i][2]}")
            return
        kind, role, _prompt, _var, _expected = self.steps[self.step_i]
        if kind == "stick":
            moved = [(abs(self.pad.moved(s, a)), s, a) for (s, a) in self.pad.info if self.pad.kind(s, a) == "stick"]
            moved = [m for m in moved if m[0] >= 0.6]
            if moved:
                _d, short, axis = max(moved)
                self.record((short, (EV_ABS, axis, sign(self.pad.moved(short, axis)))), now)
                return
        if now - self.phase_since > self.step_timeout:
            self.record(None, now)

    # --- exits

    def fn_key_side(self, slot):
        """"left"/"right" when the cfg's FN_KEY_* sends this stick click (the Brick), else None."""
        side = "left" if slot == "L3" else "right"
        fn_key = cfg_spec(f"FN_KEY_{side.upper()}", self.env)
        if fn_key and fn_key == cfg_spec(SLOT_VARS[slot], self.env):
            return side
        return None

    def longest_hold(self, now):
        held = [(now - max(since, self.hold_floor), control) for (_s, control), since in self.pad.pressed.items()
                if not self.is_power(control)]
        return max(held) if held else (0.0, None)

    def info_step(self, control):
        """Rows a D-pad press scrolls the info pane, whichever node sends it: its slot, a hat or an arrow key."""
        etype, code, direction = control
        slot = self.names.slot.get(control)
        if slot not in INFO_SCROLL:
            slot = HAT_DPAD.get((code, direction)) if etype == EV_ABS else KEY_DPAD.get(code)
        return INFO_SCROLL.get(slot, 0)

    def info_chord_down(self):
        held = {c for _s, c in self.pad.pressed}
        left = set(self.names.controls_of("L1"))
        right = set(self.names.controls_of("R1"))
        return bool(left & held and right & held)

    def tick_info(self, now):
        """L1 + R1 held together in the picture: after INFO_HOLD the device info opens. Meanwhile the exit hold
        restarts, so letting one of them go first never leaves the app."""
        if self.mode != "picture" or not self.info_chord_down():
            self.info_since = None
            return
        self.hold_floor = now
        if self.info_since is None:
            self.info_since = now
        if not self.info_open and now - self.info_since >= self.info_hold:
            self.info_open = True
            self.info_scroll = 0
            self.info_acted = now
            self.info_lines = self.device_info()
            self.event_line("device info opened (L1 + R1)")
            self.log.info("Button Reader: device info opened")
        self.dirty = True

    def begin_exit(self, reason, now):
        self.mode = "leaving"
        self.mode_since = now
        self.exit_reason = reason
        self.dirty = True
        self.log.info(f"Button Reader: exit ({reason})")
        self.event_line(f"exit: {reason}")

    def tick_switch(self, now):
        if self.switch is None:
            return
        asking = self.mode == "steps" and self.phase == "ask" and self.steps[self.step_i][0] == "switch"
        flip = self.switch.poll(now, 0.3 if asking else 1.0)
        if not flip:
            return
        text = f"Fn switch {flip[0]} -> {flip[1]}"
        self.log.info(f"Button Reader: {text}")
        self.event_line(text)
        self.recent = ([text] + self.recent)[:RECENT_LINES]
        self.dirty = True
        if asking:
            self.record(("switch", flip), now)

    def tick(self, now):
        self.tick_switch(now)
        if self.mode == "start" and now - self.mode_since >= self.start_window:
            self.mode = "picture"
            self.mode_since = now
            self.dirty = True
        elif self.mode == "steps":
            self.tick_steps(now)
        self.tick_info(now)
        if self.mode == "leaving":
            keys_held = any(c[0] == EV_KEY for _s, c in self.pad.pressed)
            if not keys_held or now - self.mode_since > self.release_wait:
                self.done = True
            return
        held, control = self.longest_hold(now)
        if held >= self.exit_hold:
            self.begin_exit(f"{self.names.describe(control)} held {self.exit_hold:.0f} s", now)

    def rescan(self):
        """Open nodes that appeared since (a USB or Bluetooth pad); one that won't open is not retried."""
        known = {n.path for n in self.nodes} | self.failed
        fresh = []
        for path in evdev.event_paths(self.roots.dev + "/input"):
            if path in known:
                continue
            try:
                fresh.append(evdev.Node(path, self.roots.sys))
            except OSError as error:
                self.failed.add(path)
                self.open_errors.append(f"{path}: cannot open ({error})")
        if not fresh:
            return
        infos, _consumers, _dt = hardware.inventory(fresh, self.roots)
        for node, info in zip(fresh, infos):
            self.nodes.append(node)
            self.infos.append(info)
            self.pad.add_node(node)
            self.log.info(f"Button Reader: new node {info.summary()}")
            self.event_line(f"new node {info.summary()}")
        self.dirty = True

    # --- screen

    def slot_state(self, slot, held):
        controls = self.names.controls_of(slot)
        if any(c in held for c in controls):
            return "on"
        if slot in self.names.absent:
            return "absent"
        for control in controls:
            if any((control[1] in n.keys) if control[0] == EV_KEY else (control[1] in n.axes) for n in self.nodes):
                return "off"
        return "unknown"

    def scene(self, now):
        s = picture.Scene()
        held = {c for _s, c in self.pad.pressed}
        m = self.manifest
        for slot, _var, _pyui in SLOTS:
            s.labels[slot] = m.control(slot).get("label") or self.names.label(slot)
            s.state[slot] = self.slot_state(slot, held)
        s.labels["FN"], s.state["FN"] = self.fn_state(held)
        raw = []
        for stick in ("LEFT", "RIGHT"):
            axes = self.stick_axes(stick)
            info = {"present": any(axes.values()), "absent": m.has(f"{stick}_STICK") is False}
            for axis, key in (("x", "dx"), ("y", "dy")):
                if axes[axis]:
                    short, code, direction = axes[axis]
                    info[key] = self.pad.deflection(short, code) * direction
                    raw.append(f"{abs_name(code)} {self.pad.values.get((short, code))}")
            s.sticks[stick] = info
        if self.mode == "start":
            s.prompt = "Press any button now for the full diagnostic"
            s.overlay = f"Picture in {max(1, math.ceil(self.start_window - (now - self.mode_since)))}"
            s.overlay_color = picture.TARGET
        elif self.mode == "steps":
            kind, role, prompt, _var, _exp = self.steps[self.step_i]
            if self.phase == "settle":
                s.prompt = "Let go of everything"
            else:
                s.prompt = f"{self.step_i + 1}/{len(self.steps)}: {prompt}"
                s.target = role
                s.prompt_color = picture.TARGET
        elif self.mode == "leaving":
            s.prompt = "Let go of the buttons"
            s.overlay = "Leaving"
        else:
            s.prompt = "Press anything"
            if self.step_results:
                ok = sum(1 for r in self.step_results if r["verdict"] in ("OK", "RECORDED"))
                s.prompt = f"Steps: {ok} of {len(self.step_results)} as the cfg expects"
                s.prompt_color = picture.GOOD if ok == len(self.step_results) else picture.WARN
        s.lines = [(m.name, picture.TARGET if m.known else picture.WARN)]  # the device first; "Unknown" stands out
        s.lines += [(text, picture.TEXT if i == 0 else picture.GRAY) for i, text in enumerate(self.recent)]
        s.line_rows = RECENT_LINES + 2
        if self.mode == "steps" and self.phase == "ask":
            left = self.step_timeout - (now - self.phase_since)
            last = self.step_results[-1] if self.step_results else None
            text = f"Skips itself in {max(0, math.ceil(left))} s"
            if last:
                text += f"   last: {last['verdict']}"
            s.lines.append((text, picture.BAD if last and last["verdict"] == "DIFFERENT" else picture.GRAY))
        else:
            others = [f"{short} {self.names.describe(c)}" for short, c in self.pad.pressed if c not in self.names.slot]
            if self.switch is not None and self.switch.readable:
                raw.append(f"Fn switch {self.switch.value}")
            s.lines.append(("Also held: " + "; ".join(others[:2]), picture.WARN) if others
                           else ("   ".join(raw) or f"{len(self.nodes)} input nodes", picture.GRAY))
        held_for, control = self.longest_hold(now)
        if self.mode != "leaving" and held_for >= self.countdown_after and control is not None:
            s.overlay = f"Exit in {max(1, math.ceil(self.exit_hold - held_for))} s"
            s.overlay_color = picture.WARN
        if self.info_since is not None and not self.info_open and now - self.info_since >= self.countdown_after:
            s.overlay = f"Device info in {max(1, math.ceil(self.info_hold - (now - self.info_since)))} s"
            s.overlay_color = picture.TARGET
        if self.info_open:
            s.prompt = "Device info"
            s.info = self.info_lines
            s.info_scroll = self.info_scroll
            s.overlay = None
        return s

    def fn_state(self, held):
        """The picture's Fn box: lit while an Fn key is held; it reads the Fn switch's position when there is one."""
        m = self.manifest
        keys = [s for s in FN_SLOTS if m.has(s)] + [s for s in ("L3", "R3") if m.control(s).get("label") == "Fn"]
        has = [m.has(s) for s in ("FN_SWITCH",) + FN_SLOTS] + [True] * bool(keys)
        label = "Fn"
        if self.switch is not None and self.switch.readable and m.has("FN_SWITCH") is not False:
            label = f"Fn {self.switch.value}"
        if any(c in held for s in keys for c in self.names.controls_of(s) + [spec_control(m.code(s))]):
            return label, "on"
        if True in has:
            return label, "off"
        return label, "absent" if all(h is False for h in has) else "unknown"

    def footer(self, now):
        if self.info_open:
            return "D-pad scrolls (left/right a page); any other button closes"
        if self.info_since is not None:
            return "Keep holding L1 + R1 for the device info"
        held_for, control = self.longest_hold(now)
        if self.mode != "leaving" and held_for >= self.countdown_after and control is not None:
            return f"Exit in {max(1, math.ceil(self.exit_hold - held_for))} s; let go to stay"
        return EXIT_HINT

    # --- main loop

    def run(self):
        try:
            m = self.manifest  # a known device switches joystickinput only when its manifest names it as a source
            if self.joystick is not None and (not m.known or m.fed_by("joystickinput")) and self.joystick.analog():
                text = f"joystickinput (pid {', '.join(map(str, self.joystick.pids))}) set to analog mode while open"
                self.log.info(f"Button Reader: {text}")
                self.event_line(text)
            self.log_inventory()
            last_rescan = last_draw = self.clock()
            while not self.done:
                if self.desktop is not None:
                    self.desktop.pump()
                    if self.desktop.quit and self.mode != "leaving":
                        self.begin_exit("Esc on the desktop", self.clock())
                        self.done = True
                fds = [n.fd for n in self.nodes]
                ready = select.select(fds, [], [], 0.02)[0] if fds else []
                if not fds:
                    time.sleep(0.02)
                now = self.clock()
                for node in self.nodes:
                    if node.fd in ready:
                        for etype, code, value in node.read():
                            self.on_event(node, etype, code, value, now)
                self.tick(now)
                if now - last_rescan > RESCAN_SECONDS and self.desktop is None:
                    self.rescan()
                    last_rescan = now
                if self.screen is not None:
                    if (self.dirty and now - last_draw >= MIN_FRAME) or now - last_draw > REDRAW_SECONDS:
                        scene = self.scene(now)
                        self.screen.show(scene, self.footer(now))
                        self.info_max = scene.info_max
                        self.dirty = False
                        last_draw = now
                    self.screen.idle(now)
        finally:
            self.close()
        return self.report_path

    def close(self):
        if self.joystick is not None:
            try:
                restored = self.joystick.restore()  # first, so nothing failing below keeps the stick out of the menu
                if restored:
                    text = f"joystickinput (pid {', '.join(map(str, restored))}) set back to keyboard mode"
                    self.log.info(f"Button Reader: {text}")
                    self.event_line(text)
            except OSError as error:
                self.log.warning(f"Button Reader: joystickinput not set back to keyboard mode ({error})")
        if self.switch is not None:
            self.switch.close()
        for (short, axis), (low, high) in sorted(self.pad.extremes.items()):
            if self.pad.kind(short, axis) in ("stick", "trigger") and low != high:
                self.log.info(f"Button Reader: {short} {abs_name(axis)} seen {low}..{high}")
        if self.report:
            try:
                self.report.line(f"{self.t():9.3f} end ({self.exit_reason or 'stopped'})")
                self.report.finish(self)
            except Exception as error:  # what didn't make it into the report must not stop the app
                self.log.warning(f"Button Reader: report incomplete ({error!r})")
                self.report.line(f"--- report stopped early: {error!r}")
            finally:
                self.report.close()
            self.log.info(f"Button Reader: report {self.report_path}")
        for node in self.nodes:
            node.close()


class PyUiCanvas:
    """picture's canvas on PyUI's Display: small, normal and big text from the theme's fonts."""

    def __init__(self):
        from display.display import Display
        from display.font_purpose import FontPurpose
        from display.render_mode import RenderMode
        self.D = Display
        small = min((FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION, FontPurpose.LIST), key=Display.get_line_height)
        if Display.get_line_height(FontPurpose.MESSAGE) <= 1.8 * Display.get_line_height(small):
            big = FontPurpose.MESSAGE
        else:
            big = FontPurpose.LIST
        self.fonts = {"small": small, "normal": FontPurpose.LIST, "big": big}
        self.align = {"center": RenderMode.MIDDLE_CENTER_ALIGNED, "left": RenderMode.MIDDLE_LEFT_ALIGNED}

    def box(self, color, x, y, w, h):
        if w >= 1 and h >= 1:
            self.D.render_box(color, int(x), int(y), int(math.ceil(w)), int(math.ceil(h)))

    def text(self, text, x, y, color, size, align):
        self.D.render_text(text, int(x), int(y), color, self.fonts[size], self.align[align])

    def text_width(self, text, size):
        return self.D.get_text_dimensions(self.fonts[size], text)[0]

    def line_height(self, size):
        return self.D.get_line_height(self.fonts[size])


class PyUiScreen:
    def __init__(self, device, desktop=False):
        from controller.controller import Controller
        from display.display import Display
        self.D = Display
        self.C = Controller
        self.w = device.screen_width()
        self.h = device.screen_height()
        self.canvas = PyUiCanvas()
        # On the desktop clear_input_queue flushes SDL's key events, which the app reads itself.
        self.clear_queue = not desktop
        self.cleared = 0.0
        self.after_present = None  # host tests capture frames here

    def show(self, scene, footer):
        self.D.clear(scene.title, bottom_bar_text=footer, render_bottom_bar_icons_and_images=False)
        top = self.D.get_top_bar_height()
        bottom = self.h - self.D.get_bottom_bar_height()
        picture.draw(self.canvas, (0, top, self.w, bottom - top), scene)
        self.D.present()
        if self.after_present:
            self.after_present(scene)

    def idle(self, now):
        if self.clear_queue and now - self.cleared > 0.5:  # PyUI's reader keeps queueing presses meanwhile
            self.C.clear_input_queue()
            self.cleared = now

    def message(self, text, ms):
        self.D.display_message(text, ms)


def report_dir(desktop):
    if os.environ.get("BUTTON_READER_REPORT_DIR"):
        return os.environ["BUTTON_READER_REPORT_DIR"]
    if desktop is not None:  # the desktop's SD card is read-only: write beside its other data
        return os.path.join(os.path.expanduser(os.environ.get("PYUI_DESKTOP_DATA", "~/.pyui-desktop")), "ButtonReader")
    return os.path.join(APP_DIR, "reports")


def run(**_kwargs):
    """PyUI's entry point. Returns when the user leaves; PyUI's menu carries on."""
    from controller.controller import Controller
    from devices.device import Device
    from utils.logger import PyUiLogger
    device = Device.get_device()
    desktop = None
    if type(device).__name__ == "DesktopDevice":
        from button_reader.desktop_keys import DesktopKeyboard
        desktop = DesktopKeyboard()
    hold = getattr(Controller, "hold_screensaver", None)
    if hold:
        hold(True)  # restarts PyUI's idle timer when released, so the menu doesn't blank on return
    log = PyUiLogger.get_logger()
    # spruce runs PyUI at WARNING unless verbose logging is on: lift it to INFO for this session only.
    levels = [(item, item.level) for item in [log] + list(log.handlers) if item.level > logging.INFO]
    for item, _level in levels:
        item.setLevel(logging.INFO)
    try:
        screen = PyUiScreen(device, desktop=desktop is not None)
        switch = FnSwitch() if desktop is None else None
        joystick = JoystickInput() if desktop is None else None
        spruce = SpruceQuery() if desktop is None else None
        session = Session(device=device, controller_interface=Controller.controller_interface, log=log,
                          screen=screen, desktop=desktop, report_dir=report_dir(desktop), switch=switch,
                          joystick=joystick, spruce=spruce)
        path = session.run()
        if path:
            shown = os.path.relpath(path, "/mnt/SDCARD") if path.startswith("/mnt/SDCARD/") else path
            screen.message(f"Report saved: {shown}", 3000)
    finally:
        for item, level in levels:
            item.setLevel(level)
        if hold:
            hold(False)
        Controller.clear_input_queue()
