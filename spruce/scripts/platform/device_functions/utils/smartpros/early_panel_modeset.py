"""Perform the first DRM modeset of the boot with a black framebuffer.

The kernel never reads the bootloader's panel state back into DRM, so the
first userspace SETCRTC after boot re-runs the whole panel init. Spending it
here, in the background of device_init, keeps it off the frontend's first
frame. Raw ioctls, no libdrm.

Holds an exclusive flock on LOCK_PATH while it is DRM master; a display
client must take that lock before opening the card.

Exits silently on any failure: the frontend then does the modeset itself.
"""

import ctypes
import fcntl
import os
import struct
import sys
from collections import namedtuple

CARD = "/dev/dri/card0"
LOCK_PATH = "/tmp/early_panel_modeset.lock"
DRM_MODE_CONNECTOR_DSI = 16
DRM_MODE_CONNECTED = 1
BPP = 32
DEPTH = 24

DRM_IOCTL_MODE_GETRESOURCES = 0xC04064A0
DRM_IOCTL_MODE_GETCONNECTOR = 0xC05064A7
DRM_IOCTL_MODE_GETENCODER = 0xC01464A6
DRM_IOCTL_MODE_CREATE_DUMB = 0xC02064B2
DRM_IOCTL_MODE_ADDFB = 0xC01C64AE
DRM_IOCTL_MODE_SETCRTC = 0xC06864A2


class Layout:
    """A kernel ioctl struct: its struct format and field names, in declaration order."""

    def __init__(self, fmt, fields):
        self.fmt = fmt
        names = fields.split()
        self.record = namedtuple("Record", names, defaults=(0,) * len(names))


MODEINFO = Layout("<I10H3I32s",
                  "clock hdisplay hsync_start hsync_end htotal hskew"
                  " vdisplay vsync_start vsync_end vtotal vscan vrefresh flags type name")
MODEINFO_SIZE = struct.calcsize(MODEINFO.fmt)
CARD_RES = Layout("<4Q8I",
                  "fb_id_ptr crtc_id_ptr connector_id_ptr encoder_id_ptr"
                  " count_fbs count_crtcs count_connectors count_encoders"
                  " min_width max_width min_height max_height")
GET_CONNECTOR = Layout("<4Q3I5I3II",
                       "encoders_ptr modes_ptr props_ptr prop_values_ptr"
                       " count_modes count_props count_encoders"
                       " encoder_id connector_id connector_type connector_type_id connection"
                       " mm_width mm_height subpixel pad")
GET_ENCODER = Layout("<5I", "encoder_id encoder_type crtc_id possible_crtcs possible_clones")
CREATE_DUMB = Layout("<6IQ", "height width bpp flags handle pitch size")
FB_CMD = Layout("<7I", "fb_id width height pitch bpp depth handle")
CRTC = Layout("<Q7I%ds" % MODEINFO_SIZE,
              "set_connectors_ptr count_connectors crtc_id fb_id x y gamma_size mode_valid mode")


def u32_array(n):
    return (ctypes.c_uint32 * max(n, 1))()


def ioctl(fd, req, layout, **fields):
    """Issue req with the named fields set (the rest zero); returns the struct the kernel wrote back."""
    buf = bytearray(struct.pack(layout.fmt, *layout.record(**fields)))
    fcntl.ioctl(fd, req, buf)
    return layout.record._make(struct.unpack(layout.fmt, buf))


def get_resources(fd):
    r = ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, CARD_RES)
    crtcs, conns, encs = u32_array(r.count_crtcs), u32_array(r.count_connectors), u32_array(r.count_encoders)
    ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, CARD_RES,
          crtc_id_ptr=ctypes.addressof(crtcs), connector_id_ptr=ctypes.addressof(conns),
          encoder_id_ptr=ctypes.addressof(encs),
          count_crtcs=r.count_crtcs, count_connectors=r.count_connectors, count_encoders=r.count_encoders)
    return list(crtcs)[:r.count_crtcs], list(conns)[:r.count_connectors]


def get_connector(fd, conn_id):
    c = ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, GET_CONNECTOR, connector_id=conn_id)
    modes = ctypes.create_string_buffer(MODEINFO_SIZE * max(c.count_modes, 1))
    props, values = u32_array(c.count_props), (ctypes.c_uint64 * max(c.count_props, 1))()
    encs = u32_array(c.count_encoders)
    c = ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, GET_CONNECTOR,
              encoders_ptr=ctypes.addressof(encs), modes_ptr=ctypes.addressof(modes),
              props_ptr=ctypes.addressof(props), prop_values_ptr=ctypes.addressof(values),
              count_modes=c.count_modes, count_props=c.count_props, count_encoders=c.count_encoders,
              connector_id=conn_id)
    first_mode = modes.raw[:MODEINFO_SIZE] if c.count_modes else None
    return c, list(encs)[:c.count_encoders], first_mode


def crtc_for(fd, encoder_ids, crtcs):
    for enc_id in encoder_ids:
        enc = ioctl(fd, DRM_IOCTL_MODE_GETENCODER, GET_ENCODER, encoder_id=enc_id)
        if enc.crtc_id:
            return enc.crtc_id
        for i, cid in enumerate(crtcs):
            if enc.possible_crtcs & (1 << i):
                return cid
    return 0


def main():
    lock = os.open(LOCK_PATH, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o666)
    fcntl.flock(lock, fcntl.LOCK_EX)
    fd = os.open(CARD, os.O_RDWR | os.O_CLOEXEC)
    try:
        return set_black_mode(fd)
    finally:
        # Drops DRM master while the lock is still held.
        os.close(fd)


def set_black_mode(fd):
    crtcs, conns = get_resources(fd)
    for conn_id in conns:
        conn, encoders, mode = get_connector(fd, conn_id)
        if conn.connector_type != DRM_MODE_CONNECTOR_DSI or conn.connection != DRM_MODE_CONNECTED or mode is None:
            continue
        crtc_id = crtc_for(fd, ([conn.encoder_id] if conn.encoder_id else []) + encoders, crtcs)
        if not crtc_id:
            return 1
        timing = MODEINFO.record._make(struct.unpack(MODEINFO.fmt, mode))
        # A fresh dumb buffer is zero-filled: the modeset shows black.
        dumb = ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, CREATE_DUMB,
                     height=timing.vdisplay, width=timing.hdisplay, bpp=BPP)
        fb = ioctl(fd, DRM_IOCTL_MODE_ADDFB, FB_CMD,
                   width=timing.hdisplay, height=timing.vdisplay, pitch=dumb.pitch,
                   bpp=BPP, depth=DEPTH, handle=dumb.handle)
        conn_arr = u32_array(1)
        conn_arr[0] = conn_id
        ioctl(fd, DRM_IOCTL_MODE_SETCRTC, CRTC,
              set_connectors_ptr=ctypes.addressof(conn_arr), count_connectors=1,
              crtc_id=crtc_id, fb_id=fb.fb_id, mode_valid=1, mode=mode)
        return 0
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except OSError as e:
        print("early_panel_modeset: %s" % e, file=sys.stderr)
        sys.exit(1)
