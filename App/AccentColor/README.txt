Accent Color
============

Recolours the active theme's accent to any colour, on the device: RGB sliders,
a hex code (PyUI's on-screen keyboard) or presets, with a live preview. When you
apply, the theme's accent images and colour keys are rewritten and spruce restarts
the menu, which loads the new colours.

Controls: Up/Down choose R, G, B, HEX or PRESET. Left/Right adjust (hold to speed
up), L1/R1 +/-16, A on HEX types a code, A elsewhere applies, B cancels.

Works with any theme that opts in by shipping an accent/ folder (for example
NextUI Style and NextUI Style Light in spruceUI/PyUI-Themes). Other themes show a
message and are left untouched.

For theme authors: the accent/ folder
-------------------------------------
accent/manifest.json
    {
      "templates": { "<skin folder>": ["<image>.png", ...], ... },
      "midtone":   ["bg-list-l.png"],          optional: drawn in a mid-tone accent
      "mode":      "dark" | "light",           optional, default "dark"
      "palette":   { "bg", "ink", "sub", "card", "track" }   optional, #RRGGBB
    }
accent/<skin folder>/<image>.png.tpl, one per listed image:
    b"NUTP", u16 width, u16 height, u16 entry count (little endian),
    entry count x 6 bytes (alpha, c0 r, c0 g, c0 b, k_accent, k_seltext),
    then zlib-compressed palette indices, one byte per pixel.
    A pixel's premultiplied colour is c0 + k_accent*ACCENT/255 + k_seltext*SEL/255,
    where SEL is black or white, whichever reads better on the accent.
accent/accent.json
    { "accent": "#RRGGBB" }, the current colour (the picker starts from it).

Screen sizes the theme doesn't ship: PyUI's theme patcher scales skin/ into a
skin_<W>x<H> folder the first time the theme loads on such a device (e.g. Powkiddy
V10 at 480x320). After recolouring, the app rescales the accent images into those
folders too, with the patcher's own sizing rules and PyUI's image utils.

On apply, only these keys change: grid.selectedcolor (palette "ink") and
list.selectedcolor (SEL) in every config*.json, and colors.selection, .accent and
.text_selected in igm.json. Any other setting the user changed is kept.

The recolouring (accent_engine.py) is plain Python (struct + zlib, no Pillow), so
it runs on spruce's bundled Python on every device. Start-up follows App/Cheevos:
launch.sh sets up the platform the way App/PyUI/launch.sh does, and
accent_picker.py brings PyUI up with its own log
(Saves/spruce/accentcolor-<platform>.log) and its own PyUI state file
(Saves/accentcolor/pyui-state.json).

Templates are built off-device by rendering every accent-dependent image with probe
colours; the NextUI Style themes were built that way (author: Diego Mussi).
