"""Button Reader in PyUI's process: start screen, guided steps (full diagnostic), live picture.
It never calls Controller.get_input(), so PyUI's game switcher, hotkeys and screensaver stay out.
"""
import logging
import math
import os
import select
import time

from button_reader import VERSION, evdev, hardware, picture
from button_reader.names import (EV_ABS, EV_KEY, EV_SW, HAT_FIRST, HAT_LAST, KEY_POWER, SLOT_VAR, SLOTS,
                                 STICKS, SW_NAMES, Names, abs_name, cfg_spec, face_print_text, face_prompt,
                                 pyui_tables, sign, spec_control, stick_axis)

EXIT_HOLD = 10.0
COUNTDOWN_AFTER = 3.0
START_WINDOW = 3.0
STEP_TIMEOUT = 15.0
SETTLE_MAX = 3.0
RELEASE_WAIT = 3.0
RESCAN_SECONDS = 2.0
REDRAW_SECONDS = 0.25
MIN_FRAME = 1 / 30.0
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
             ("VOL_UP", "Press VOL+"), ("VOL_DOWN", "Press VOL-")]
STICK_STEPS = [("LEFT_X", "LEFT", "x", "Push the LEFT stick fully RIGHT, then let go"),
               ("LEFT_Y", "LEFT", "y", "Push the LEFT stick fully DOWN, then let go"),
               ("RIGHT_X", "RIGHT", "x", "Push the RIGHT stick fully RIGHT, then let go"),
               ("RIGHT_Y", "RIGHT", "y", "Push the RIGHT stick fully DOWN, then let go")]


class Pad:
    """Held controls, axis values and the extremes seen, across every node."""

    def __init__(self, names):
        self.names = names
        self.values, self.extremes, self.info, self.pressed = {}, {}, {}, {}
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
        mid, half = (info["max"] + info["min"]) / 2.0, (info["max"] - info["min"]) / 2.0
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
            low_high[0], low_high[1] = min(low_high[0], value), max(low_high[1], value)
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
                 nodes=None, roots=None, report_dir=None, clock=time.monotonic, desktop=None):
        self.env = dict(os.environ if env is None else env)
        self.desktop = desktop
        if desktop is not None:
            from button_reader.desktop_keys import ENV
            for key, value in ENV.items():
                self.env.setdefault(key, value)
        controls, sticks = pyui_tables(controller_interface, device)
        self.names = Names(self.env, controls, sticks)
        self.platform = self.env.get("PLATFORM") or "unknown"
        aliases = ""
        try:
            aliases = ", ".join(device.get_device_names())
        except Exception:
            pass
        self.device_desc = f"{type(device).__name__ if device is not None else 'none'}" + (f" ({aliases})" if aliases else "")
        self.log = log or logging.getLogger("ButtonReader")
        self.roots = roots or hardware.Roots()
        self.clock, self.screen = clock, screen
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
        self.exit_hold, self.countdown_after, self.start_window = EXIT_HOLD, COUNTDOWN_AFTER, START_WINDOW
        self.step_timeout, self.settle_max, self.release_wait = STEP_TIMEOUT, SETTLE_MAX, RELEASE_WAIT
        self.started = self.clock()
        self.mode, self.mode_since = "start", self.started
        self.verbose, self.report, self.report_path = False, None, None
        self.steps, self.step_i, self.phase, self.phase_since = [], 0, "settle", self.started
        self.step_results, self.answers, self.last_record = [], {}, None
        self.recent, self.logged_axis, self._ranked, self.failed = [], {}, [], set()
        self.done, self.exit_reason, self.dirty = False, None, True

    # --- logging

    def log_inventory(self):
        self.log.info(f"Button Reader {VERSION}: {len(self.nodes)} input nodes on {self.platform} ({self.device_desc}), "
                      f"{face_print_text(self.platform)}")
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
            if HAT_FIRST <= code <= HAT_LAST or abs(value - self.logged_axis.get((node.short, code), info.get("value", 0))) >= step:
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
                    self.recent = ([text] + self.recent)[:3]
                    self.on_press(short, control, now)
            elif kind == "switch":
                text = f"{item[0]} switch {SW_NAMES.get(item[1], item[1])} = {item[2]}"
                self.log.info(f"Button Reader: {text}")
                self.event_line(text)

    def on_press(self, short, control, now):
        if self.mode == "start" and not self.is_power(control):
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
        if not last or now - last[0] > 0.6 or last[2] not in set(self.names.controls_of("SELECT") + self.names.controls_of("START")):
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
        select_controls, start_controls = self.names.controls_of("SELECT"), self.names.controls_of("START")
        return bool(select_controls and start_controls and held & set(select_controls) and held & set(start_controls))

    def stick_axes(self, stick):
        """{"x": (short, axis, sign), "y": ...} for one stick, from the cfg/PyUI or the default axes."""
        out = {"x": None, "y": None}
        info = self.names.sticks.get(stick)
        defaults = {s: (dx, dy) for s, _vx, _vy, dx, dy in STICKS}[stick]
        count = self.env.get("DEVICE_NUM_ANALOG_STICKS", "")
        for k, axis in enumerate(("x", "y")):
            want = info[axis] if info and info[axis] else None
            if want is None and info is None and count != "0":
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
        try:
            self.report = Report(self.report_dir, self.platform)
            self.report_path = self.report.path
            self.report.header(self)
            self.report.inventory(self, full=False)
            self.report.line("--- events (seconds since start)")
        except OSError as error:
            self.log.warning(f"Button Reader: no report ({error}); the steps still run")
            self.report = None
        names, steps = self.names, []
        for slot, prompt in KEY_STEPS:
            if slot in names.absent or (slot == "HOME" and not names.controls_of("HOME")):
                continue
            prompt = prompt or face_prompt(slot, self.platform)
            steps.append(("key", slot, prompt, SLOT_VAR[slot], spec_control(cfg_spec(SLOT_VAR[slot], self.env))))
        count = self.env.get("DEVICE_NUM_ANALOG_STICKS", "")
        sticks = int(count) if count.isdigit() else sum(1 for s in ("LEFT", "RIGHT") if any(self.stick_axes(s).values()))
        for role, stick, axis, prompt in STICK_STEPS[:2 * min(sticks, 2)]:
            var = dict((s, (vx, vy)) for s, vx, vy, _dx, _dy in STICKS)[stick][0 if axis == "x" else 1]
            steps.append(("stick", role, prompt, var, stick_axis(cfg_spec(var, self.env))))
        self.steps, self.step_i = steps, 0
        self.mode, self.mode_since, self.phase, self.phase_since = "steps", now, "settle", now
        self.log.info(f"Button Reader: full diagnostic, {len(steps)} guided steps, report {self.report_path}")
        if not steps:
            self.mode = "picture"

    def record(self, answer, now):
        kind, role, prompt, var, expected = self.steps[self.step_i]
        if kind == "key":
            want = self.names.describe(expected) if expected else "nothing (cfg unset)"
            got = f"{answer[0]} {self.names.describe(answer[1])}" if answer else "no input"
            same = bool(answer) and answer[1] == expected
        else:
            want = f"{abs_name(expected[0])} {'+' if expected[1] > 0 else '-'}" if expected else "nothing (cfg unset)"
            got = (f"{answer[0]} {abs_name(answer[1][1])} {'+' if answer[1][2] > 0 else '-'}" if answer else "no input")
            same = bool(answer) and (answer[1][1], answer[1][2]) == tuple(expected or ())
        verdict = "NO INPUT" if not answer else "RECORDED" if expected is None else "OK" if same else "DIFFERENT"
        self.last_record = (now, role, answer[1] if answer else None, self.answers.get(role))
        if answer:
            self.answers[role] = answer
        if kind == "stick" or expected is None:
            want += f" ({var})"  # a key's description already names its cfg variable
        self.step_results.append({"prompt": prompt, "var": var, "want": want, "got": got, "verdict": verdict})
        self.event_line(f"step {self.step_i + 1} {verdict}: {prompt}: expected {want}, got {got}")
        self.log.info(f"Button Reader: step {verdict}: {prompt}: expected {want}, got {got}")
        self.step_i += 1
        self.phase, self.phase_since, self.dirty = "settle", now, True
        if self.step_i >= len(self.steps):
            self.mode, self.mode_since = "picture", now

    def tick_steps(self, now):
        if self.phase == "settle":
            if self.at_rest() or now - self.phase_since > self.settle_max:
                self.phase, self.phase_since, self.dirty = "ask", now, True
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

    def longest_hold(self, now):
        held = [(now - since, control) for (_s, control), since in self.pad.pressed.items() if not self.is_power(control)]
        return max(held) if held else (0.0, None)

    def begin_exit(self, reason, now):
        self.mode, self.mode_since, self.exit_reason, self.dirty = "leaving", now, reason, True
        self.log.info(f"Button Reader: exit ({reason})")
        self.event_line(f"exit: {reason}")

    def tick(self, now):
        if self.mode == "start" and now - self.mode_since >= self.start_window:
            self.mode, self.mode_since, self.dirty = "picture", now, True
        elif self.mode == "steps":
            self.tick_steps(now)
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
        for slot, _var, _pyui in SLOTS:
            s.labels[slot] = self.names.label(slot)
            s.state[slot] = self.slot_state(slot, held)
        raw = []
        for stick, click in (("LEFT", "L3"), ("RIGHT", "R3")):
            axes = self.stick_axes(stick)
            info = {"present": any(axes.values()), "click": s.state[click], "label": s.labels[click]}
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
                s.prompt, s.target = f"{self.step_i + 1}/{len(self.steps)}: {prompt}", role
                s.prompt_color = picture.TARGET
        elif self.mode == "leaving":
            s.prompt, s.overlay = "Let go of the buttons", "Leaving"
        else:
            s.prompt = "Press anything"
            if self.step_results:
                ok = sum(1 for r in self.step_results if r["verdict"] in ("OK", "RECORDED"))
                s.prompt = f"Steps: {ok} of {len(self.step_results)} as the cfg expects"
                s.prompt_color = picture.GOOD if ok == len(self.step_results) else picture.WARN
        s.lines = [(text, picture.TEXT if i == 0 else picture.GRAY) for i, text in enumerate(self.recent)]
        if self.mode == "steps" and self.phase == "ask":
            left = self.step_timeout - (now - self.phase_since)
            last = self.step_results[-1] if self.step_results else None
            text = f"Skips itself in {max(0, math.ceil(left))} s"
            if last:
                text += f"   last: {last['verdict']}"
            s.lines.append((text, picture.BAD if last and last["verdict"] == "DIFFERENT" else picture.GRAY))
        else:
            others = [f"{short} {self.names.describe(c)}" for short, c in self.pad.pressed if c not in self.names.slot]
            s.lines.append(("Also held: " + "; ".join(others[:2]), picture.WARN) if others
                           else ("   ".join(raw) or f"{len(self.nodes)} input nodes", picture.GRAY))
        held_for, control = self.longest_hold(now)
        if self.mode != "leaving" and held_for >= self.countdown_after and control is not None:
            s.overlay = f"Exit in {max(1, math.ceil(self.exit_hold - held_for))} s"
            s.overlay_color = picture.WARN
        return s

    def footer(self, now):
        held_for, control = self.longest_hold(now)
        if self.mode != "leaving" and held_for >= self.countdown_after and control is not None:
            return f"Exit in {max(1, math.ceil(self.exit_hold - held_for))} s; let go to stay"
        return EXIT_HINT

    # --- main loop

    def run(self):
        self.log_inventory()
        last_rescan = last_draw = self.clock()
        try:
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
                        self.screen.show(self.scene(now), self.footer(now))
                        self.dirty, last_draw = False, now
                    self.screen.idle(now)
        finally:
            self.close()
        return self.report_path

    def close(self):
        for (short, axis), (low, high) in sorted(self.pad.extremes.items()):
            if self.pad.kind(short, axis) in ("stick", "trigger") and low != high:
                self.log.info(f"Button Reader: {short} {abs_name(axis)} seen {low}..{high}")
        if self.report:
            try:
                self.report.line(f"{self.t():9.3f} end ({self.exit_reason or 'stopped'})")
                self.report.finish(self)
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
        big = FontPurpose.MESSAGE if Display.get_line_height(FontPurpose.MESSAGE) <= 1.8 * Display.get_line_height(small) \
            else FontPurpose.LIST
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
        self.D, self.C = Display, Controller
        self.w, self.h = device.screen_width(), device.screen_height()
        self.canvas = PyUiCanvas()
        # On the desktop clear_input_queue flushes SDL's key events, which the app reads itself.
        self.clear_queue, self.cleared = not desktop, 0.0
        self.after_present = None  # host tests capture frames here

    def show(self, scene, footer):
        self.D.clear("Button Reader", bottom_bar_text=footer, render_bottom_bar_icons_and_images=False)
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
        session = Session(device=device, controller_interface=Controller.controller_interface,
                          log=log, screen=screen, desktop=desktop, report_dir=report_dir(desktop))
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
