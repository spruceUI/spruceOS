"""Device manifests: devices/<PLATFORM>.json lists every control a device has, where its signal comes from and
what it lacks (format in devices/README.md). A device without one gets the same shape, derived from its cfg.
"""
import fnmatch
import json
import os

from button_reader.names import ABSENT, SLOTS, cfg_spec, parse_spec, stick_axis

SCHEMA = "spruce-button-reader-device/1"
DEVICES_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "devices")
STICK_SLOTS = ("LEFT_STICK", "RIGHT_STICK")
EXTRA_SLOTS = ("FN_SWITCH", "FN_LEFT", "FN_RIGHT", "LID")
ALL_SLOTS = [slot for slot, _var, _pyui in SLOTS] + list(STICK_SLOTS) + list(EXTRA_SLOTS)
SLOT_VARS = dict((slot, var) for slot, var, _pyui in SLOTS)
SLOT_VARS.update({"FN_LEFT": "FN_KEY_LEFT", "FN_RIGHT": "FN_KEY_RIGHT"})
STICK_VARS = {"LEFT_STICK": ("STICK_RIGHT", "STICK_DOWN"), "RIGHT_STICK": ("STICK_RIGHT_2", "STICK_DOWN_2")}
FN_CLICK = {"FN_LEFT": "L3", "FN_RIGHT": "R3"}  # where a cfg's Fn key shares the click's code (the Brick)
UNKNOWN = "Unknown"
FEED_GROUPS = [("face buttons", ("BOTTOM", "RIGHT", "TOP", "LEFT")),
               ("D-pad", ("DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT"))]
FEED_NAMES = {"SELECT": "Select", "START": "Start", "MENU": "Menu", "HOME": "Home", "VOL_UP": "VOL+",
              "VOL_DOWN": "VOL-", "POWER": "Power", "LEFT_STICK": "left stick", "RIGHT_STICK": "right stick",
              "FN_SWITCH": "Fn switch", "FN_LEFT": "left Fn key", "FN_RIGHT": "right Fn key", "LID": "lid"}


class Manifest:
    """One device's controls and sources. known is False when it was derived from the cfg."""

    def __init__(self, data, path=None, model=None, error=None):
        self.data = data
        self.path = path
        self.known = path is not None
        self.error = error
        self.model = model
        self.platform = data.get("platform", "")
        self.sources = data.get("sources", {})
        self.controls = data.get("controls", {})
        self.absent = data.get("absent", {})
        self.face_print = data.get("face_print", "nintendo")

    @property
    def name(self):
        """The model when the cfg names one of the manifest's models, else the manifest's name; "Unknown" without."""
        if not self.known:
            return UNKNOWN
        return self.model or self.data.get("name") or self.platform

    def has(self, slot):
        """True / False, or None when it can't be told (no manifest and no cfg value, or a model we can't tell)."""
        if slot in self.absent:
            return False
        control = self.controls.get(slot)
        if control is None:
            return False if self.known else None
        models = control.get("models")
        if models:
            return None if self.model is None else self.model in models
        return True if self.known else control.get("known", True)

    def control(self, slot):
        return self.controls.get(slot) or {}

    def code(self, slot):
        """The manifest's (type, code, value) for a key slot, or None."""
        return parse_spec(self.control(slot).get("code"))

    def stick_count(self):
        """Sticks the device has; None when it can't be told."""
        has = [self.has(s) for s in STICK_SLOTS]
        if None in has:
            return None
        return sum(has)

    def source_of(self, slot):
        sid = self.control(slot).get("source")
        return sid, self.sources.get(sid) if sid else None

    def node_names(self, sid):
        source = self.sources.get(sid) or {}
        return [n for n in [source.get("node")] + list(source.get("match", [])) if n]

    def matches(self, sid, node_name):
        return any(fnmatch.fnmatchcase(node_name, pattern) for pattern in self.node_names(sid))

    def fed_by(self, daemon):
        return [sid for sid, s in self.sources.items() if s.get("fed_by") == daemon]

    def feeds(self, sid):
        """What a source carries on this unit, short ("face buttons, D-pad, L1, VOL+"), or "nothing here"."""
        slots = [s for s in ALL_SLOTS if self.control(s).get("source") == sid and self.has(s) is not False]
        names = []
        for label, group in FEED_GROUPS:
            if all(g in slots for g in group):
                names.append(label)
                slots = [s for s in slots if s not in group]
        names += [FEED_NAMES.get(s, s) for s in slots]
        return ", ".join(names) if names else "nothing here"

    def over_cfg(self, slot):
        """The stick's manifest entry when it says the hardware's axes win over the cfg's (over_cfg), else None."""
        control = self.control(slot)
        return control if slot in STICK_VARS and control.get("over_cfg") else None

    def cfg_differences(self, env):
        """[(slot, manifest value, cfg value)] where both name a code (or stick axis) and they differ."""
        out = []
        for slot, var in SLOT_VARS.items():
            mine = self.code(slot)
            theirs = cfg_spec(var, env)
            if mine and theirs not in (None, ABSENT) and mine != theirs:
                out.append((slot, self.control(slot).get("code"), env.get(var)))
        for slot, (var_x, var_y) in STICK_VARS.items():
            control = self.control(slot)
            for axis, var in (("x", var_x), ("y", var_y)):
                mine = stick_axis(parse_spec(control.get(axis)))
                theirs = stick_axis(cfg_spec(var, env))
                if mine and theirs and mine != theirs:
                    used = " (Button Reader uses the manifest's)" if self.over_cfg(slot) else ""
                    out.append((f"{slot} {axis}", control.get(axis) + used, env.get(var)))
        return out


def load(env, folder=None):
    platform = env.get("PLATFORM", "")
    path = os.path.join(folder or DEVICES_DIR, f"{platform}.json")
    if not platform or not os.path.exists(path):
        return from_cfg(env)
    try:
        with open(path) as fh:
            data = json.load(fh)
        if data.get("schema") != SCHEMA or data.get("platform") != platform:
            raise ValueError(f"schema {data.get('schema')!r}, platform {data.get('platform')!r}")
    except (OSError, ValueError) as error:
        return from_cfg(env, f"{os.path.basename(path)} unreadable ({error})")
    models = data.get("models", [])
    named = squash(env.get("SPRUCE_DEVICE_NAME", ""))
    model = next((m for m in models if squash(m) == named), models[0] if len(models) == 1 else None)
    return Manifest(data, path, model)


def squash(name):
    """'RG35XX SP' and 'RG35XXSP' are the same model: compare without case, spaces or punctuation."""
    return "".join(ch for ch in name.lower() if ch.isalnum())


def from_cfg(env, error=None):
    """What the cfg tells: a code is a control, DOESNT_EXIST is absent, anything else can't be told."""
    controls = {}
    absent = {}
    for slot, var in SLOT_VARS.items():
        spec = cfg_spec(var, env)
        click = FN_CLICK.get(slot)
        if spec == ABSENT:
            absent[slot] = f"cfg {var}=DOESNT_EXIST"
        elif spec is None:
            controls[slot] = {"code": None, "known": None, "from": "cfg unset"}
        elif click and spec == cfg_spec(SLOT_VARS[click], env):
            absent[slot] = f"{var} is {click}'s code: that Fn key is the {click} step"
        else:
            controls[slot] = {"code": env.get(var), "from": "cfg"}
    count = env.get("DEVICE_NUM_ANALOG_STICKS", "")
    for i, slot in enumerate(STICK_SLOTS):
        x, y = (env.get(v) for v in STICK_VARS[slot])
        if count.isdigit() and i >= int(count):
            absent[slot] = f"DEVICE_NUM_ANALOG_STICKS={count}"
        else:
            controls[slot] = {"x": x, "y": y, "known": True if count.isdigit() else None, "from": "cfg"}
    for slot in ("FN_SWITCH", "LID"):
        controls[slot] = {"known": None, "from": "not in the cfg"}
    data = {"schema": SCHEMA, "platform": env.get("PLATFORM", ""), "controls": controls, "absent": absent}
    return Manifest(data, None, None, error)
