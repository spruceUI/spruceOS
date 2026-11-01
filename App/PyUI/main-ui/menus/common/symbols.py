"""Button glyphs for UI prompts (promptfont).

The {A}/{B}/{X}/{Y} placeholders in a translated prompt swap for glyphs at render time, so
no lang file ever carries a font's codepoints and a translator keeps the freedom to reorder
the buttons. button_labels() returns the line as (is_symbol, run) segments; the renderer
draws the symbol runs with the bundled promptfont.ttf (SIL OFL - see
Licenses/fonts/promptfont.txt) and the rest with the theme's list font. No registry of
"every symbol": a line says for itself which run is a glyph.

Codepoints follow promptfont's own glyphs.json mapping, NOT the Unicode names those
codepoints carry: U+21D3 is promptfont's "xbox-a", not the Unicode double arrow. The
upstream index is the only authority here - the Unicode name says nothing about what the
font draws. These are the Xbox set - each letter inside a circle - not U+21A4-A7, the
generic four-circle cluster that only shows which position is pressed.
"""

BTN_A = "⇓"   # U+21D3 xbox-a
BTN_B = "⇒"   # U+21D2 xbox-b
BTN_X = "⇐"   # U+21D0 xbox-x
BTN_Y = "⇑"   # U+21D1 xbox-y

# A translator swaps the letters for their own words and may reorder them freely;
# button_labels() does the rest at render time.
BUTTON_PLACEHOLDERS = {"{A}": BTN_A, "{B}": BTN_B, "{X}": BTN_X, "{Y}": BTN_Y}


def button_labels(text):
    """Turn "{A} Yes {B} No" into [(False, ""), (True, BTN_A), (False, " Yes "), ...].

    A text with no placeholder comes back as one non-symbol segment, which keeps the
    renderer's single-render fast path intact.
    """
    segments = []
    current = ""
    i = 0
    while i < len(text):
        for placeholder, glyph in BUTTON_PLACEHOLDERS.items():
            if text.startswith(placeholder, i):
                if current:
                    segments.append((False, current))
                    current = ""
                segments.append((True, glyph))
                i += len(placeholder)
                break
        else:
            current += text[i]
            i += 1
    if current:
        segments.append((False, current))
    return segments


def glyph_runs(glyphs):
    """Turn a bare sequence of button glyphs into segments, one press per run,
    separated by a single space - the shape button_labels() returns."""
    segments = []
    for glyph in glyphs:
        if segments:
            segments.append((False, " "))
        segments.append((True, glyph))
    return segments
