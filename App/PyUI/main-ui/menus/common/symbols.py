"""Single source of truth for UI symbol glyphs (promptfont, FontPurpose.SYMBOL).

Theme fonts can miss these codepoints, so any line holding one is split into
runs and the symbol runs are drawn with the bundled promptfont.ttf (SIL OFL -
see Licenses/fonts/promptfont.txt).

Codepoints follow promptfont's upstream mapping (its glyphs.json), NOT the
Unicode names those codepoints carry: U+21A7 is promptfont's "gamepad-a", not
the Unicode arrow "d". The upstream index is the only authority here - the
Unicode name of the codepoint says nothing about what the font draws.
"""

# Face buttons: promptfont's Xbox set - each letter inside a circle. These are
# the lettered buttons, not U+21A4-A7, which are the generic four-circle
# cluster that only shows which position is pressed and carries no letter.
BTN_A = "⇓"   # U+21D3 xbox-a
BTN_B = "⇒"   # U+21D2 xbox-b
BTN_X = "⇐"   # U+21D0 xbox-x
BTN_Y = "⇑"   # U+21D1 xbox-y
BTN_START = "⇸"    # U+21F8 gamepad-start
BTN_SELECT = "⇷"   # U+21F7 gamepad-select
BTN_HOME = "⇹"     # U+21F9 gamepad-home

# D-pad: promptfont's Xbox set, matching the Xbox face buttons above.
DPAD_LEFT = "≺"   # U+227A xbox-dpad-left
DPAD_UP = "≻"     # U+227B xbox-dpad-up
DPAD_RIGHT = "≼"  # U+227C xbox-dpad-right
DPAD_DOWN = "≽"   # U+227D xbox-dpad-down
DPAD = "⊄"        # U+2284 xbox-dpad, unpressed

# Plain arrows. Kept in the symbol set because a theme font may omit them and
# they turn into tofu, but prefer the d-pad glyphs when drawing a direction.
ARROW_UP = "↑"    # U+2191
ARROW_DOWN = "↓"  # U+2193
ARROW_LEFT = "←"  # U+2190
ARROW_RIGHT = "→" # U+2192

# promptfont has no check-mark U+2713 at all (it renders as tofu); its
# check-mark is U+2714.
CHECK = "✔"

KONAMI_ARROWS = (DPAD_UP * 2 + DPAD_DOWN * 2
                 + DPAD_LEFT + DPAD_RIGHT + DPAD_LEFT + DPAD_RIGHT)

# B A START SELECT, space-separated, all as glyphs.
KONAMI = (KONAMI_ARROWS + " " + BTN_B + " " + BTN_A
          + " " + BTN_START + " " + BTN_SELECT)

# Every glyph that must be drawn with FontPurpose.SYMBOL.
SYMBOL_GLYPHS = frozenset([
    DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT,
    ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT,
    BTN_A, BTN_B, BTN_X, BTN_Y,
    BTN_START, BTN_SELECT, BTN_HOME,
    CHECK,
])


def is_symbol_char(char):
    return char in SYMBOL_GLYPHS


def split_symbol_runs(text):
    """Split text into [(is_symbol, run)] of consecutive same-font characters.

    Empty text -> []. A line with no symbol in it comes back as a single
    non-symbol run, which is what keeps the plain-render fast path intact.
    """
    runs = []
    current_is_symbol = None
    current = []
    for char in text or "":
        char_is_symbol = is_symbol_char(char)
        if current_is_symbol is None or char_is_symbol != current_is_symbol:
            if current:
                runs.append((current_is_symbol, "".join(current)))
            current_is_symbol = char_is_symbol
            current = [char]
        else:
            current.append(char)
    if current:
        runs.append((current_is_symbol, "".join(current)))
    return runs
