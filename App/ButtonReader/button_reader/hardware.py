"""What sits behind each input node: sysfs identity, its device-tree node, and the GPIO (or ADC
channel) behind each key. Every probe is best effort; a missing file gives "unknown", never an error.
"""
import os
import re
import struct

BUS_NAMES = {0x03: "USB", 0x05: "Bluetooth", 0x06: "virtual", 0x19: "host", 0x1C: "I2C"}
DEBUG_LINE = re.compile(r"^\s*gpio-(\d+)\s+\((.*?)\|(.*?)\s*\)\s+(in|out)\s+(hi|lo)(.*)$")
DEBUG_CHIP = re.compile(r"^(gpiochip\d+): GPIOs (\d+)-(\d+), (?:parent: )?(?:\w+/)?([^,]*),\s*([^:]*):")


class Roots:
    """Where sysfs, procfs, the device tree and debugfs are: the real ones, or a host test's."""

    def __init__(self, base=""):
        self.sys = base + "/sys"
        self.proc = base + "/proc"
        self.dev = base + "/dev"
        self.dt = base + "/proc/device-tree"
        self.dt_sysfs = base + "/sys/firmware/devicetree/base"
        self.debug_gpio = base + "/sys/kernel/debug/gpio"


def _read(path, mode="rb"):
    try:  # text that isn't UTF-8 (a debugfs gpio label) reads with replacement marks
        with open(path, mode, **({} if "b" in mode else {"errors": "replace"})) as fh:
            return fh.read()
    except OSError:
        return None


def _u32s(data):
    return list(struct.unpack(f">{len(data) // 4}I", data[:len(data) // 4 * 4])) if data else []


def _strings(data):
    return [s.decode("utf-8", "replace") for s in (data or b"").split(b"\0") if s]


def _realpath(path):
    return os.path.realpath(path) if os.path.exists(path) else None


class DeviceTree:
    def __init__(self, root):
        self.root = root
        self._phandles = None
        self._names = None

    def prop(self, path, name):
        return _read(os.path.join(self.root + path, name))

    def strings(self, path, name):
        return _strings(self.prop(path, name))

    def u32s(self, path, name):
        return _u32s(self.prop(path, name))

    def children(self, path):
        try:
            entries = sorted(os.listdir(self.root + path))
        except OSError:
            return []
        return [f"{path.rstrip('/')}/{e}" for e in entries if os.path.isdir(os.path.join(self.root + path, e))]

    def phandle(self, number):
        if self._phandles is None:
            self._phandles = {}
            for top, dirs, files in os.walk(self.root):
                for name in ("phandle", "linux,phandle"):
                    if name in files:
                        value = _u32s(_read(os.path.join(top, name)))
                        if value:
                            relative = os.path.relpath(top, self.root).replace(os.sep, "/")
                            self._phandles[value[0]] = "/" + relative.lstrip("./")
        return self._phandles.get(number)

    def label(self, path):
        """The node's alias or dts label (gpio2), else its name without the unit address."""
        if self._names is None:
            self._names = {}
            for table in ("/__symbols__", "/aliases"):
                try:
                    entries = os.listdir(self.root + table)
                except OSError:
                    continue
                for entry in entries:
                    target = _strings(self.prop(table, entry))
                    if target:
                        self._names[target[0]] = entry
        return self._names.get(path) or os.path.basename(path).split("@")[0]


def gpio_bases(roots, dt):
    """{controller DT path: base of its Linux GPIO numbers} from sysfs, else from debugfs."""
    bases = {}
    try:
        chips = os.listdir(os.path.join(roots.sys, "class/gpio"))
    except OSError:
        chips = []
    for chip in chips:
        if not chip.startswith("gpiochip"):
            continue
        folder = os.path.join(roots.sys, "class/gpio", chip)
        base = (_read(os.path.join(folder, "base"), "r") or "").strip()
        of_node = _realpath(os.path.join(folder, "device/of_node"))
        if base.isdigit() and of_node and of_node.startswith(os.path.realpath(roots.dt_sysfs)):
            bases[of_node[len(os.path.realpath(roots.dt_sysfs)):] or "/"] = int(base)
    dt.phandle(0)  # builds the index of every referenced node, the GPIO controllers among them
    controllers = set((dt._phandles or {}).values())
    for line in (_read(roots.debug_gpio, "r") or "").splitlines():
        match = DEBUG_CHIP.match(line)
        if not match:
            continue
        unit = match.group(4).split(".")[0]
        for path in controllers:
            if path.endswith("@" + unit) or path.endswith("@" + unit.lstrip("0")):
                bases.setdefault(path, int(match.group(2)))
    return bases


def debug_consumers(roots):
    """{consumer label: (gpio number, direction, level, rest)} from /sys/kernel/debug/gpio."""
    found = {}
    for line in (_read(roots.debug_gpio, "r") or "").splitlines():
        match = DEBUG_LINE.match(line)
        if match:
            found.setdefault(match.group(3).strip(), (int(match.group(1)), match.group(4), match.group(5),
                                                      match.group(6).strip()))
    return found


def resolve_gpio(dt, cells, bases):
    """One gpios specifier (phandle + the controller's #gpio-cells) as a readable pin."""
    if not cells:
        return None
    controller = dt.phandle(cells[0])
    if controller is None:
        return {"pin": f"phandle {cells[0]:#x} (no such node)", "controller": None, "linux": None, "active": "?"}
    ncells = (dt.u32s(controller, "#gpio-cells") or [2])[0]
    args = cells[1:1 + ncells]
    compat = " ".join(dt.strings(controller, "compatible"))
    bank = dt.label(controller)
    flags = args[-1] if len(args) >= 2 else 0
    if ncells >= 3:  # Allwinner: <&pio bank pin flags>; r_pio's first bank is L
        first = "L" if "r-pinctrl" in compat or "r_pio" in bank else "A"
        pin = f"P{chr(ord(first) + args[0])}{args[1]}"
        offset = args[0] * 32 + args[1]
    else:
        number = args[0] if args else 0
        offset = number
        digits = re.sub(r"\D", "", bank)
        pin = f"GPIO{digits}_P{chr(65 + number // 8)}{number % 8}" if "rockchip" in compat and digits \
            else f"{bank} pin {number}"
    base = bases.get(controller)
    return {"pin": pin, "controller": controller, "linux": f"gpio{base + offset}" if base is not None else None,
            "active": "active low" if flags & 1 else "active high"}


def key_wiring(dt, of_node, bases):
    """{key code: [wiring dict]} for the children of an input device's DT node."""
    wiring = {}
    if not of_node:
        return wiring
    for child in [of_node] + dt.children(of_node):
        codes = dt.u32s(child, "linux,code")
        if not codes:
            continue
        entry = {"dt": child, "label": (dt.strings(child, "label") or [""])[0]}
        gpio_cells = dt.u32s(child, "gpios") or dt.u32s(child, "gpio")
        threshold = dt.u32s(child, "press-threshold-microvolt")
        if gpio_cells:
            entry["gpio"] = resolve_gpio(dt, gpio_cells, bases)
        elif threshold:
            entry["adc"] = f"ADC key, pressed at {threshold[0]} uV"
        wiring.setdefault(codes[0], []).append(entry)
    return wiring


def adc_channels(dt, of_node):
    """[(name, ADC node, channel)] from io-channels / io-channel-names (analog sticks, adc-keys)."""
    cells = dt.u32s(of_node, "io-channels")
    names = dt.strings(of_node, "io-channel-names")
    out = []
    i = 0
    n = 0
    while i < len(cells):
        adc = dt.phandle(cells[i])
        width = (dt.u32s(adc, "#io-channel-cells") or [1])[0] if adc else 1
        channel = cells[i + 1] if width and i + 1 < len(cells) else None
        out.append((names[n] if n < len(names) else f"#{n}", adc or f"phandle {cells[i]:#x}", channel))
        i += 1 + width
        n += 1
    return out


def uinput_feeders(roots):
    """[(pid, comm)] of processes holding /dev/uinput: the daemons behind virtual pads."""
    feeders = []
    try:
        pids = [p for p in os.listdir(roots.proc) if p.isdigit()]
    except OSError:
        return feeders
    for pid in pids:
        fd_dir = os.path.join(roots.proc, pid, "fd")
        try:
            links = [os.readlink(os.path.join(fd_dir, fd)) for fd in os.listdir(fd_dir)]
        except OSError:
            continue
        if any(link.endswith("/uinput") for link in links):
            comm = (_read(os.path.join(roots.proc, pid, "comm"), "r") or "?").strip()
            feeders.append((int(pid), comm))
    return sorted(feeders)


class NodeInfo:
    """sysfs identity and DT wiring of one node, for the log and the report."""

    def __init__(self, node, roots, dt, bases, feeders):
        self.node = node
        base = os.path.join(roots.sys, "class/input", node.short)
        self.sysfs = _realpath(base) or "?"
        self.parent = _realpath(os.path.join(base, "device/device"))
        self.driver = None
        self.of_node = None
        if self.parent:
            driver = _realpath(os.path.join(self.parent, "driver"))
            self.driver = os.path.basename(driver) if driver else None
            of_node = _realpath(os.path.join(self.parent, "of_node"))
            dt_root = os.path.realpath(roots.dt_sysfs)
            if of_node and of_node.startswith(dt_root):
                self.of_node = of_node[len(dt_root):] or "/"
        self.virtual = "/devices/virtual/" in self.sysfs or (self.parent is None and node.ident[0] == 0x06)
        self.bus = BUS_NAMES.get(node.ident[0], f"bus {node.ident[0]:#x}")
        self.compatible = dt.strings(self.of_node, "compatible") if self.of_node else []
        self.wiring = key_wiring(dt, self.of_node, bases)
        self.adc = adc_channels(dt, self.of_node) if self.of_node else []
        self.feeders = feeders if self.virtual else []

    def summary(self):
        n = self.node
        parts = [f"{n.path} \"{n.name}\"", f"phys {n.phys or '-'}", f"sysfs {self.sysfs}",
                 f"id {self.bus} {n.ident[1]:04x}:{n.ident[2]:04x} v{n.ident[3]:04x}"]
        if self.driver:
            parts.append(f"driver {self.driver}")
        if self.of_node:
            parts.append(f"DT {self.of_node} ({', '.join(self.compatible) or 'no compatible'})")
        elif self.virtual:
            who = ", ".join(f"{c} (pid {p})" for p, c in self.feeders) or "a daemon"
            parts.append(f"virtual node fed by {who}: not GPIO-wired")
        return "; ".join(parts)

    def wiring_text(self, code, consumers=None):
        """How one key code is wired, in one line."""
        entries = self.wiring.get(code)
        if entries:
            texts = []
            for e in entries:
                where = f"{e['dt']}" + (f" \"{e['label']}\"" if e["label"] else "")
                if "gpio" in e and e["gpio"]:
                    g = e["gpio"]
                    linux = g["linux"]
                    live = (consumers or {}).get(e["label"])
                    if live and not linux:
                        linux = f"gpio{live[0]}"
                    level = f", now {live[2]}" if live else ""
                    texts.append(f"{g['pin']} ({linux or 'Linux number unknown'}, {g['active']}{level}) via {where}")
                elif "adc" in e:
                    texts.append(f"{e['adc']} via {where}")
                else:
                    texts.append(f"no GPIO in {where}")
            return "; ".join(texts)
        if self.virtual:
            who = ", ".join(c for _p, c in self.feeders) or "a daemon"
            return f"not GPIO-wired (virtual node fed by {who})"
        if self.bus in ("USB", "Bluetooth"):
            return f"not GPIO-wired ({self.bus} device)"
        if self.of_node:
            return f"no GPIO listed for it in {self.of_node} (driver {self.driver or '?'})"
        return "no device-tree node for its device (e.g. a PMIC power key): GPIO unknown"


def inventory(nodes, roots=None):
    """NodeInfo for every node, plus debugfs's GPIO consumers when debugfs is mounted."""
    roots = roots or Roots()
    dt = DeviceTree(roots.dt)
    any_dt = os.path.isdir(roots.dt)
    if any_dt:
        dt.phandle(0)  # index the tree once
    bases = gpio_bases(roots, dt) if any_dt else {}
    feeders = None
    infos = []
    for node in nodes:
        info = NodeInfo(node, roots, dt, bases, [])
        if info.virtual:
            feeders = uinput_feeders(roots) if feeders is None else feeders
            info.feeders = feeders
        infos.append(info)
    return infos, debug_consumers(roots), dt
