"""Recolour a theme that ships accent templates (accent/) to any accent colour, on the device.

Pure standard library (struct + zlib) so it runs on spruce's bundled Python,
which has no Pillow. Each accent-dependent image ships as a small template
(.tpl) built by make_accent_templates.py:

    magic  b"NUTP"
    u16    width, height, entry_count            (little endian)
    entry_count x 6 bytes: alpha, c0_r, c0_g, c0_b, k_accent, k_seltext
    rest   zlib-compressed palette index per pixel (1 byte each)

A pixel's premultiplied colour is   c0 + k_accent*ACCENT/255 + k_seltext*SELTEXT/255,
where SELTEXT is black or white (whichever reads better on the accent).
"""
import json
import os
import struct
import zlib

MAGIC = b"NUTP"


def parse_hex(value):
    v = value.strip().lstrip("#")
    if len(v) != 6:
        raise ValueError("expected #RRGGBB")
    return tuple(int(v[i:i + 2], 16) for i in (0, 2, 4))


def to_hex(rgb):
    return "#%02X%02X%02X" % tuple(rgb)


def selected_text_color(rgb):
    """Black text on light accents, white on dark ones (same rule as the theme builder)."""
    lum = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
    return (0, 0, 0) if lum > 150 else (255, 255, 255)


def _rel_lum(c):
    def ch(v):
        v /= 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2])


def midtone(c, target=0.18, mode="dark"):
    """Same as the theme builder: bring the accent to mid luminance for the large highlight /
    keyboard text box, so both black and white text read on it. Dark themes darken light
    accents; light themes (dark keyboard text) lighten dark accents instead."""
    c = tuple(c[:3])
    if mode == "light":
        if _rel_lum(c) >= target:
            return c
        lo, hi = 0.0, 1.0
        for _ in range(24):
            m = (lo + hi) / 2
            if _rel_lum(tuple(v + (255 - v) * m for v in c)) < target:
                lo = m
            else:
                hi = m
        return tuple(int(round(v + (255 - v) * hi)) for v in c)
    if _rel_lum(c) <= target:
        return c
    lo, hi = 0.0, 1.0
    for _ in range(24):
        m = (lo + hi) / 2
        if _rel_lum(tuple(v * m for v in c)) < target:
            lo = m
        else:
            hi = m
    return tuple(int(round(v * lo)) for v in c)


def _load_tpl(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] != MAGIC:
        raise ValueError(f"not a template: {path}")
    w, h, n = struct.unpack_from("<HHH", data, 4)
    off = 10
    entries = [struct.unpack_from("6B", data, off + i * 6) for i in range(n)]
    idx = zlib.decompress(data[off + n * 6:])
    return w, h, entries, idx


def _tables(entries, acc, sel):
    tr, tg, tb, ta = bytearray(256), bytearray(256), bytearray(256), bytearray(256)
    for i, (a, c0r, c0g, c0b, ka, ks) in enumerate(entries):
        ta[i] = a
        if a == 0:
            continue
        for t, c0, ac, sc in ((tr, c0r, acc[0], sel[0]), (tg, c0g, acc[1], sel[1]), (tb, c0b, acc[2], sel[2])):
            premult = c0 + ka * ac / 255.0 + ks * sc / 255.0
            t[i] = max(0, min(255, int(round(premult * 255.0 / a))))
    return bytes(tr), bytes(tg), bytes(tb), bytes(ta)


def _png_chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)


def render_tpl(path, acc, sel):
    """Return PNG bytes for one template recoloured to acc/sel."""
    w, h, entries, idx = _load_tpl(path)
    tr, tg, tb, ta = _tables(entries, acc, sel)
    rgba = bytearray(w * h * 4)
    rgba[0::4] = idx.translate(tr)
    rgba[1::4] = idx.translate(tg)
    rgba[2::4] = idx.translate(tb)
    rgba[3::4] = idx.translate(ta)
    stride = w * 4
    raw = b"".join(b"\x00" + bytes(rgba[y * stride:(y + 1) * stride]) for y in range(h))
    return (b"\x89PNG\r\n\x1a\n"
            + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + _png_chunk(b"IDAT", zlib.compress(raw, 6))
            + _png_chunk(b"IEND", b""))


def _write_atomic(path, data, mode="wb"):
    tmp = path + ".tmp"
    with open(tmp, mode) as fh:
        fh.write(data)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def _patch_json(path, patch_fn):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return False
    patch_fn(data)
    _write_atomic(path, json.dumps(data, indent=4), mode="w")
    return True


def current_accent(theme_dir):
    try:
        with open(os.path.join(theme_dir, "accent", "accent.json"), "r", encoding="utf-8") as fh:
            return parse_hex(json.load(fh)["accent"])
    except (OSError, ValueError, KeyError):
        return (255, 255, 255)


def theme_palette(theme_dir):
    """Colours the picker uses for its own screen (dark or light theme)."""
    dark = {"mode": "dark", "bg": "#000000", "ink": "#FFFFFF", "sub": "#8A8A8A",
            "card": "#222428", "track": "#3C3E46"}
    try:
        with open(os.path.join(theme_dir, "accent", "manifest.json"), "r", encoding="utf-8") as fh:
            m = json.load(fh)
        dark.update(m.get("palette", {}))
        dark["mode"] = m.get("mode", "dark")
    except (OSError, ValueError):
        pass
    return dark


def template_folders(theme_dir):
    with open(os.path.join(theme_dir, "accent", "manifest.json"), "r", encoding="utf-8") as fh:
        return list(json.load(fh)["templates"])


def apply_accent(theme_dir, acc, folders=None, progress=None):
    """Recolour the theme in place. folders=None means every resolution folder.

    Only the accent colours are touched in the config files, so any other theme
    setting the user changed on the device is kept.
    """
    acc = tuple(acc)
    sel = selected_text_color(acc)
    acc_hex, sel_hex = to_hex(acc), to_hex(sel)
    with open(os.path.join(theme_dir, "accent", "manifest.json"), "r", encoding="utf-8") as fh:
        manifest = json.load(fh)

    mid = midtone(acc, mode=manifest.get("mode", "dark"))
    ink_hex = theme_palette(theme_dir)["ink"]   # white on the dark version, near-black on light
    use_mid = set(manifest.get("midtone", []))
    jobs = [(folder, name) for folder, names in manifest["templates"].items()
            if folders is None or folder in folders for name in names]
    for i, (folder, name) in enumerate(jobs):
        tpl = os.path.join(theme_dir, "accent", folder, name + ".tpl")
        out = os.path.join(theme_dir, folder, name)
        _write_atomic(out, render_tpl(tpl, mid if name in use_mid else acc, sel))
        if progress:
            progress(i + 1, len(jobs))

    def patch_config(d):
        d.setdefault("grid", {})["selectedcolor"] = ink_hex  # selected tab + keyboard text
        d.setdefault("list", {})["selectedcolor"] = sel_hex   # text on the highlight

    for f in os.listdir(theme_dir):
        if f.startswith("config") and f.endswith(".json"):
            _patch_json(os.path.join(theme_dir, f), patch_config)

    def patch_igm(d):
        c = d.setdefault("colors", {})
        c["selection"] = acc_hex + "FF"
        c["accent"] = acc_hex + "FF"
        c["text_selected"] = sel_hex + "FF"

    _patch_json(os.path.join(theme_dir, "igm.json"), patch_igm)
    _write_atomic(os.path.join(theme_dir, "accent", "accent.json"),
                  json.dumps({"accent": acc_hex}), mode="w")
    return len(jobs)
