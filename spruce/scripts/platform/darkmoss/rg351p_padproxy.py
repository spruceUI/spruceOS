#!/usr/bin/python3 -I
# spruce on the RG351P (dArkMoss): a virtual pad that outlives the real one.
# Started and supervised by RG351P.sh (_rg351p_padproxy_start).
#
# The internal pad (OpenSimHardware OSH PB Controller, USB 1209:3100) loses
# power in suspend and comes back as a new input device on every wake.
# RetroArch and PPSSPP re-open it; programs that open it once at start (vtree,
# Songo's Godot runtime, most SDL apps) keep the dead device and lose their
# controls. This daemon grabs the real pad (EVIOCGRAB) and mirrors it into a
# uinput device with the same name and IDs, so every mapping keyed on the pad
# (SDL GUID, RetroArch autoconfig, spruce's cfg) still matches, and that
# device never goes away. When the real pad disappears it releases whatever
# was held, waits for the pad to come back and grabs it again.
#
# While the virtual pad exists, a runtime udev rule (/run/udev/rules.d, gone
# at reboot and removed again on exit) stops tagging the real pad as a
# joystick, so SDL, Godot and RetroArch see one pad, the virtual one. The
# virtual device's phys is "rg351p-padproxy": that is how spruce, which finds
# the pad by name, tells the two apart.
import errno, fcntl, os, select, signal, struct, subprocess, sys, time

PAD_NAME = "OpenSimHardware OSH PB Controller"
PHYS = b"rg351p-padproxy"
RULE = "/run/udev/rules.d/99-rg351p-padproxy.rules"
RULE_TEXT = (
    "# spruce rg351p_padproxy.py: the real pad is mirrored by a virtual one;\n"
    "# hide the real one from joystick scans while that runs, and make sure\n"
    "# the virtual one (keyboard keys included, like the real pad) is a joystick.\n"
    'SUBSYSTEM=="input", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="3100", '
    'ENV{ID_INPUT_JOYSTICK}="", ENV{ID_INPUT_KEYBOARD}="", ENV{ID_INPUT_KEY}=""\n'
    'SUBSYSTEM=="input", ATTRS{phys}=="rg351p-padproxy", '
    'ENV{ID_INPUT_JOYSTICK}="1", ENV{ID_INPUT_KEYBOARD}="", ENV{ID_INPUT_KEY}=""\n'
)

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT = 0
KEY_CNT, ABS_CNT = 0x300, 0x40

def _ioc(d, t, nr, size):
    return (d << 30) | (size << 16) | (ord(t) << 8) | nr

def EVIOCGBIT(ev, size): return _ioc(2, 'E', 0x20 + ev, size)
def EVIOCGABS(code): return _ioc(2, 'E', 0x40 + code, 24)
EVIOCGID = _ioc(2, 'E', 0x02, 8)
EVIOCGRAB = _ioc(1, 'E', 0x90, 4)
UI_SET_EVBIT = _ioc(1, 'U', 100, 4)
UI_SET_KEYBIT = _ioc(1, 'U', 101, 4)
UI_SET_ABSBIT = _ioc(1, 'U', 103, 4)
UI_SET_PHYS = _ioc(1, 'U', 108, 8)
UI_DEV_CREATE = _ioc(0, 'U', 1, 0)
UI_DEV_DESTROY = _ioc(0, 'U', 2, 0)

EVENT = struct.Struct("qqHHi")   # struct input_event on aarch64

def log(msg):
    print(msg, flush=True)

def bits(fd, ev, count):
    buf = bytearray((count + 7) // 8)
    fcntl.ioctl(fd, EVIOCGBIT(ev, len(buf)), buf)
    return [i for i in range(count) if buf[i // 8] >> (i % 8) & 1]

def find_pad():
    """The real pad's event node (never our own virtual one), or None."""
    for entry in sorted(os.listdir("/sys/class/input")):
        if not entry.startswith("event"):
            continue
        base = "/sys/class/input/%s/device/" % entry
        try:
            with open(base + "name") as f:
                if f.read().strip() != PAD_NAME:
                    continue
            with open(base + "phys") as f:
                if f.read().strip() == PHYS.decode():
                    continue
        except OSError:
            continue
        return "/dev/input/" + entry
    return None

def open_pad(path):
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    try:
        fcntl.ioctl(fd, EVIOCGRAB, 1)
    except OSError:
        os.close(fd)
        raise
    return fd

def create_virtual(pad_fd):
    # Every key the real pad declares, its keyboard collection's keys included:
    # RetroArch's udev driver numbers buttons from the lowest key code, so the
    # pad's 15 keyboard keys put its buttons at 15-26, which its autoconfig
    # and spruce's RetroArch binds expect.
    keys = bits(pad_fd, EV_KEY, KEY_CNT)
    axes = bits(pad_fd, EV_ABS, ABS_CNT)
    absinfo = {}
    for a in axes:
        buf = bytearray(24)
        fcntl.ioctl(pad_fd, EVIOCGABS(a), buf)
        absinfo[a] = struct.unpack("6i", buf)   # value min max fuzz flat res
    ident = bytearray(8)
    fcntl.ioctl(pad_fd, EVIOCGID, ident)
    bustype, vendor, product, version = struct.unpack("4H", ident)

    ufd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(ufd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(ufd, UI_SET_EVBIT, EV_ABS)
    for k in keys:
        fcntl.ioctl(ufd, UI_SET_KEYBIT, k)
    for a in axes:
        fcntl.ioctl(ufd, UI_SET_ABSBIT, a)
    fcntl.ioctl(ufd, UI_SET_PHYS, PHYS + b"\0")
    absmax, absmin, absfuzz, absflat = ([0] * ABS_CNT for _ in range(4))
    for a, (_, lo, hi, fuzz, flat, _) in absinfo.items():
        absmin[a], absmax[a], absfuzz[a], absflat[a] = lo, hi, fuzz, flat
    dev = struct.pack("80s4HI", PAD_NAME.encode(), bustype, vendor, product, version, 0)
    dev += struct.pack("%di" % (4 * ABS_CNT), *(absmax + absmin + absfuzz + absflat))
    os.write(ufd, dev)
    fcntl.ioctl(ufd, UI_DEV_CREATE)
    centre = {a: (lo + hi) // 2 for a, (_, lo, hi, _, _, _) in absinfo.items()}
    log("virtual pad created: %d buttons, %d axes, id %04x:%04x:%04x:%04x"
        % (len(keys), len(axes), bustype, vendor, product, version))
    return ufd, centre, axes

def emit(ufd, etype, code, value):
    os.write(ufd, EVENT.pack(0, 0, etype, code, value))

def release_all(ufd, held, axes, centre):
    for k in list(held):
        emit(ufd, EV_KEY, k, 0)
    for a, v in list(axes.items()):
        rest = 0 if a in (0x10, 0x11, 0x12, 0x13) else centre.get(a, 0)
        if v != rest:
            emit(ufd, EV_ABS, a, rest)
    emit(ufd, EV_SYN, SYN_REPORT, 0)
    held.clear()
    axes.clear()

def sync_axes(pfd, ufd, axis_list, axes):
    """Copy the real pad's current axis values. A new uinput device starts
    with every axis at 0 (both sticks pushed up-left on this pad) and a stick
    at rest sends nothing, so without this the virtual sticks stay pushed
    until moved: RetroArch's menu fought the "held" stick and games saw a
    stuck direction. Also run on every re-attach after a wake."""
    for a in axis_list:
        buf = bytearray(24)
        try:
            fcntl.ioctl(pfd, EVIOCGABS(a), buf)
        except OSError:
            continue
        value = struct.unpack("6i", buf)[0]
        axes[a] = value
        emit(ufd, EV_ABS, a, value)
    emit(ufd, EV_SYN, SYN_REPORT, 0)

def udev(*args):
    subprocess.run(["udevadm"] + list(args), stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, timeout=15)

def retag(present):
    """Hide (present) or show again the real pad to joystick scans."""
    try:
        if present:
            os.makedirs(os.path.dirname(RULE), exist_ok=True)
            with open(RULE, "w") as f:
                f.write(RULE_TEXT)
        elif os.path.exists(RULE):
            os.unlink(RULE)
        udev("control", "--reload")
        udev("trigger", "--action=change", "--subsystem-match=input")
        udev("settle", "-t", "5")
    except Exception as e:
        log("retag failed: %s" % e)

def main():
    ufd = None
    centre = {}
    axis_list = []
    held, axes = set(), {}

    def stop(*_):
        if ufd is not None:
            try:
                fcntl.ioctl(ufd, UI_DEV_DESTROY)
            except OSError:
                pass
        retag(False)
        sys.exit(0)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    while True:
        path = find_pad()
        if not path:
            time.sleep(0.25)
            continue
        try:
            pfd = open_pad(path)
        except OSError as e:
            log("cannot open %s: %s" % (path, e))
            time.sleep(0.5)
            continue
        if ufd is None:
            # Rules first, so the virtual pad is a joystick from its first udev event.
            retag(True)
            try:
                ufd, centre, axis_list = create_virtual(pfd)
            except OSError as e:
                log("cannot create the virtual pad: %s" % e)
                os.close(pfd)
                retag(False)
                time.sleep(2)
                continue
            udev("settle", "-t", "5")
        sync_axes(pfd, ufd, axis_list, axes)
        log("mirroring %s" % path)
        while True:
            try:
                select.select([pfd], [], [])
                data = os.read(pfd, EVENT.size * 64)
            except OSError as e:
                if e.errno == errno.EAGAIN:
                    continue
                log("%s gone (%s)" % (path, os.strerror(e.errno)))
                break
            if not data:
                log("%s gone (EOF)" % path)
                break
            for off in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _, _, etype, code, value = EVENT.unpack_from(data, off)
                if etype == EV_KEY:
                    if value == 2:
                        continue        # no autorepeat on the virtual pad
                    (held.add if value else held.discard)(code)
                elif etype == EV_ABS:
                    axes[code] = value
                elif etype != EV_SYN:
                    continue            # MSC scancodes and the like
                emit(ufd, etype, code, value)
        try:
            os.close(pfd)
        except OSError:
            pass
        release_all(ufd, held, axes, centre)

if __name__ == "__main__":
    main()
