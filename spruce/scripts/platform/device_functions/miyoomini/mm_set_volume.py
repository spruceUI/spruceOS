#!/mnt/SDCARD/spruce/bin/python/bin/python3.10
import os
import fcntl
import ctypes
import sys

MI_AO_SETVOLUME = 0x4008690b
MI_AO_GETVOLUME = 0xc008690c
MI_AO_SETMUTE   = 0x4008690d

MIN_RAW_VALUE = -60
MAX_RAW_VALUE = 0


class Buf2(ctypes.Structure):
    _fields_ = [
        ("unknown", ctypes.c_int),
        ("value", ctypes.c_int),
    ]


class Buf1(ctypes.Structure):
    _fields_ = [
        ("size", ctypes.c_uint64),
        ("ptr", ctypes.c_uint64),
    ]


def set_mute(fd, mute_on):
    buf2 = Buf2(0, 1 if mute_on else 0)
    buf1 = Buf1(ctypes.sizeof(buf2), ctypes.addressof(buf2))
    fcntl.ioctl(fd, MI_AO_SETMUTE, buf1)

def set_volume_raw(value):
    fd = os.open("/dev/mi_ao", os.O_RDWR)
    print(f"Setting raw volume to {value}")
    try:
        buf2 = Buf2(0, 0)
        buf1 = Buf1(ctypes.sizeof(buf2), ctypes.addressof(buf2))

        # get current volume
        fcntl.ioctl(fd, MI_AO_GETVOLUME, buf1)

        # clamp
        if value > MAX_RAW_VALUE:
            value = MAX_RAW_VALUE
        elif value < MIN_RAW_VALUE:
            value = MIN_RAW_VALUE
        
        # mute logic
        if value > MIN_RAW_VALUE:
            set_mute(fd, False)
        elif value <= MIN_RAW_VALUE:
            set_mute(fd, True)


        # set volume
        buf2.value = value
        fcntl.ioctl(fd, MI_AO_SETVOLUME, buf1)
        print(f"raw volume: {buf2.value}")

        return value

    finally:
        os.close(fd)


def main():
    if len(sys.argv) != 2:
        print("Usage:")
        print("  set_volume.py 0-20   # 0=mute, 20=max")
        sys.exit(1)

    try:
        ui_value = int(sys.argv[1])

        if ui_value < 0:
            ui_value = 0
        elif ui_value > 20:
            ui_value = 20

        # mute case
        if ui_value == 0:
            set_volume_raw(-60)   # lowest raw value
            return

        # map 1-20 to -57.0
        raw = -30 + int(ui_value * 1.5)
        set_volume_raw(raw)

    except ValueError:
        print("Invalid volume value")
        sys.exit(1)



if __name__ == "__main__":
    main()

