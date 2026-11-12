"""Raw evdev nodes. struct input_event is "llHHi" in native sizes (16 bytes on armhf, 24 on
aarch64); the signed value keeps negative axis readings negative.
"""
import fcntl
import glob
import os
import re
import struct

from button_reader.names import EV_ABS, EV_KEY

EVENT = struct.Struct("llHHi")
KEY_MAX = 0x2FF
ABS_MAX = 0x3F
KEY_BYTES = (KEY_MAX + 8) // 8
ABS_BYTES = (ABS_MAX + 8) // 8


def _ior(nr, size):
    return 0x80000000 | (size << 16) | (ord("E") << 8) | nr


EVIOCGID = _ior(0x02, 8)
EVIOCGNAME = _ior(0x06, 256)
EVIOCGPHYS = _ior(0x07, 256)
EVIOCGUNIQ = _ior(0x08, 256)


def EVIOCGBIT(ev, size):  # noqa: N802 (the kernel macro's name)
    return _ior(0x20 + ev, size)


def EVIOCGABS(axis):  # noqa: N802
    return _ior(0x40 + axis, 24)


def bits(buf):
    return [i * 8 + b for i, byte in enumerate(buf) for b in range(8) if byte >> b & 1]


def _text(buf):
    return bytes(buf).split(b"\0", 1)[0].decode("utf-8", "replace")


def read_text(path):
    try:
        with open(path, "r", errors="replace") as fh:
            return fh.read().strip()
    except OSError:
        return None


class Node:
    """One input node: identity, key and axis capabilities (with absinfo) and an fd to read."""

    def __init__(self, path, sys_root="/sys"):
        self.path = path
        self.short = os.path.basename(path)
        self.fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        sysdir = os.path.join(sys_root, "class/input", self.short, "device")
        self.name = self._ioctl_text(EVIOCGNAME) or read_text(f"{sysdir}/name") or "?"
        self.phys = self._ioctl_text(EVIOCGPHYS) or read_text(f"{sysdir}/phys") or ""
        self.uniq = self._ioctl_text(EVIOCGUNIQ) or read_text(f"{sysdir}/uniq") or ""
        try:
            self.ident = struct.unpack("4H", fcntl.ioctl(self.fd, EVIOCGID, bytes(8)))
        except OSError:
            self.ident = tuple(int(read_text(f"{sysdir}/id/{k}") or "0", 16)
                               for k in ("bustype", "vendor", "product", "version"))
        self.keys = []
        self.axes = {}
        try:
            self.keys = bits(fcntl.ioctl(self.fd, EVIOCGBIT(EV_KEY, KEY_BYTES), bytes(KEY_BYTES)))
            for axis in bits(fcntl.ioctl(self.fd, EVIOCGBIT(EV_ABS, ABS_BYTES), bytes(ABS_BYTES))):
                value, lo, hi, fuzz, flat, res = struct.unpack(
                    "6i", fcntl.ioctl(self.fd, EVIOCGABS(axis), bytes(24)))
                self.axes[axis] = {"value": value, "min": lo, "max": hi, "fuzz": fuzz,
                                   "flat": flat, "res": res}
        except OSError:
            pass

    def _ioctl_text(self, request):
        try:
            return _text(fcntl.ioctl(self.fd, request, bytes(256)))
        except OSError:
            return ""

    def read(self):
        """Every pending event as (type, code, value); [] when there is none."""
        try:
            data = os.read(self.fd, EVENT.size * 64)
        except (BlockingIOError, InterruptedError):
            return []
        except OSError:
            return []  # unplugged: the node stays listed, silent
        return [EVENT.unpack_from(data, off)[2:] for off in range(0, len(data) - EVENT.size + 1, EVENT.size)]

    def close(self):
        try:
            os.close(self.fd)
        except OSError:
            pass


class PipeNode(Node):
    """A node fed through a pipe: the desktop keyboard, and fake boards in host tests."""

    def __init__(self, short, name, keys=(), axes=None, ident=(0x19, 0, 0, 0), phys=""):
        self.path = f"/dev/input/{short}"
        self.short = short
        self.name = name
        self.phys = phys
        self.uniq = ""
        self.ident = tuple(ident)
        self.keys = sorted(keys)
        self.axes = {a: dict({"value": 0, "fuzz": 0, "flat": 0, "res": 0}, **info)
                     for a, info in (axes or {}).items()}
        self.fd, self.write_fd = os.pipe()
        os.set_blocking(self.fd, False)

    def send(self, etype, code, value):
        os.write(self.write_fd, EVENT.pack(0, 0, etype, code, value) + EVENT.pack(0, 0, 0, 0, 0))

    def close(self):
        for fd in (self.fd, self.write_fd):
            try:
                os.close(fd)
            except OSError:
                pass


def event_paths(dev_root="/dev/input"):
    return sorted(glob.glob(os.path.join(dev_root, "event*")),
                  key=lambda p: int(re.sub(r"\D", "", os.path.basename(p)) or 0))


def open_nodes(paths, sys_root="/sys", errors=None):
    nodes = []
    for path in paths:
        try:
            nodes.append(Node(path, sys_root))
        except OSError as error:
            if errors is not None:
                errors.append(f"{path}: cannot open ({error})")
    return nodes
