"""The controller picture, on its own dark panel so it reads the same under any theme.
Shapes are built from boxes: PyUI's Display has no circle primitive.
"""
import math

PANEL = (20, 22, 28)
BODY = (40, 44, 54)
KEY = (64, 70, 84)
OUTLINE = (160, 166, 180)
TEXT = (238, 238, 242)
DIM = (96, 100, 112)
ON = (80, 205, 120)
ON_TEXT = (8, 24, 12)
TARGET = (95, 165, 255)
WARN = (250, 185, 60)
BAD = (245, 100, 90)
GOOD = (120, 215, 140)
GRAY = (165, 168, 178)


class Scene:
    """What one frame shows: the state of each slot and stick, plus the text around them."""

    def __init__(self):
        self.labels = {}       # slot -> label
        self.state = {}        # slot -> "on" | "off" | "absent" | "unknown"
        self.sticks = {}       # "LEFT"/"RIGHT" -> {"present", "dx", "dy", "absent"}
        self.title = "Button Reader"  # PyUI's top bar; the device's name is the first of the lines
        self.target = None     # slot or "LEFT_X"... being asked for in a guided step
        self.prompt = ""
        self.prompt_color = TEXT
        self.lines = []        # [(text, color)] under the picture
        self.line_rows = 0     # rows kept for lines, filled or not, so the picture doesn't move as they fill
        self.overlay = None    # big centred text (exit countdown, start screen)
        self.overlay_color = WARN
        self.info = None       # [(text, color)]: the device info pane, drawn instead of the picture
        self.info_scroll = 0
        self.info_max = None   # set by the drawing: the last row the pane can scroll to


# Two arrangements in units u: "tall" puts the sticks under the D-pad and face buttons (a
# vertical handheld); "wide" puts everything in one row. The one with the larger u wins.
# The top row: L3, a gap, L1 L2, the volume keys, R2 R1, a gap, R3; no Power, since pressing it puts the device
# to sleep. Every element is always drawn: what a device lacks is grayed out. The middle holds Select/Start over
# Menu, Home and Fn.
SHAPES = {
    "tall": {"size": (22.4, 11.0), "body": (-10, 1.6, 20, 9.3), "row": 0.75,
             "top": {"L3": (-10.1, 2.0), "L1": (-7.15, 2.5), "L2": (-4.45, 2.5), "VOL_DOWN": (-1.1, 1.7),
                     "VOL_UP": (1.1, 1.7), "R2": (4.45, 2.5), "R1": (7.15, 2.5), "R3": (10.1, 2.0)},
             "dpad": (-6.2, 4.4), "face": (6.2, 4.4), "sticks": {"LEFT": (-2.9, 8.2), "RIGHT": (2.9, 8.2)},
             "middle": (3.4, 4.9)},
    "wide": {"size": (26.0, 7.5), "body": (-11.9, 1.6, 23.8, 5.7), "row": 0.75,
             "top": {"L3": (-11.9, 2.0), "L1": (-8.9, 2.6), "L2": (-6.0, 2.6), "VOL_DOWN": (-1.25, 2.0),
                     "VOL_UP": (1.25, 2.0), "R2": (6.0, 2.6), "R1": (8.9, 2.6), "R3": (11.9, 2.0)},
             "dpad": (-5.6, 4.3), "face": (5.6, 4.3), "sticks": {"LEFT": (-9.7, 4.3), "RIGHT": (9.7, 4.3)},
             "middle": (3.3, 4.8)},
}
SHORT = {"Select": "Sel", "Start": "St", "Menu": "M", "Home": "H", "Vol+": "+", "Vol-": "-"}


class Layout:
    """Element shapes for a picture area, in the arrangement that draws them largest."""

    def __init__(self, x, y, w, h):
        name = max(SHAPES, key=lambda k: min(w / SHAPES[k]["size"][0], h / (SHAPES[k]["size"][1] + 0.5)))
        shape = SHAPES[name]
        sw, sh = shape["size"]
        u = min(w / sw, h / (sh + 0.5))
        ox = x + w / 2.0
        oy = y + (h - sh * u) / 2.0
        self.name = name
        self.u = u
        self.ox = ox
        self.oy = oy
        bx, by, bw, bh = shape["body"]
        self.body = (ox + bx * u, oy + by * u, bw * u, bh * u)
        r = {}

        def rect(slot, cx, cy, rw, rh):
            r[slot] = ("rect", ox + cx * u - rw * u / 2, oy + cy * u - rh * u / 2, rw * u, rh * u)

        for slot, (cx, rw) in shape["top"].items():
            rect(slot, cx, shape["row"], rw, 1.05)
        arm = 1.25
        dx0, dy0 = shape["dpad"]
        for slot, dx, dy in (("DPAD_UP", 0, -1), ("DPAD_DOWN", 0, 1), ("DPAD_LEFT", -1, 0), ("DPAD_RIGHT", 1, 0)):
            rect(slot, dx0 + dx * (arm + 0.06), dy0 + dy * (arm + 0.06), arm, arm)
        self.dpad_center = (ox + dx0 * u, oy + dy0 * u, arm * u)
        fx, fy = shape["face"]
        for slot, dx, dy in (("TOP", 0, -1), ("RIGHT", 1, 0), ("BOTTOM", 0, 1), ("LEFT", -1, 0)):
            r[slot] = ("circle", ox + (fx + dx * 1.35) * u, oy + (fy + dy * 1.35) * u, 0.72 * u)
        upper, lower = shape["middle"]
        rect("SELECT", -1.45, upper, 2.4, 0.9)
        rect("START", 1.45, upper, 2.4, 0.9)
        for slot, cx in (("MENU", -2.2), ("HOME", 0.0), ("FN", 2.2)):
            rect(slot, cx, lower, 2.0, 0.9)
        self.rects = r
        self.stick = {s: (ox + cx * u, oy + cy * u, 1.65 * u) for s, (cx, cy) in shape["sticks"].items()}


def fill_circle(canvas, cx, cy, radius, color):
    radius = max(radius, 1)
    step = max(1, int(radius) // 16)
    y = -radius
    while y < radius:
        mid = y + step / 2.0
        half = math.sqrt(max(radius * radius - mid * mid, 0))
        canvas.box(color, cx - half, cy + y, 2 * half, step)
        y += step


def fill_round_rect(canvas, x, y, w, h, radius, color):
    radius = max(0, min(radius, w / 2, h / 2))
    canvas.box(color, x + radius, y, w - 2 * radius, h)
    canvas.box(color, x, y + radius, w, h - 2 * radius)
    for cx, cy in ((x + radius, y + radius), (x + w - radius, y + radius),
                   (x + radius, y + h - radius), (x + w - radius, y + h - radius)):
        fill_circle(canvas, cx, cy, radius, color)


def _colors(state, targeted):
    """(outline, fill, text) for a slot state."""
    if state == "on":
        return ON, ON, ON_TEXT
    if state == "absent":
        return DIM, BODY, DIM
    outline = TARGET if targeted else (OUTLINE if state == "off" else DIM)
    return outline, KEY if state == "off" else BODY, TEXT if state == "off" else GRAY


def draw_slot(canvas, shape, label, state, targeted, thick):
    outline, fill, text = _colors(state, targeted)
    t = thick * (2 if targeted else 1)
    if shape[0] == "circle":
        _, cx, cy, radius = shape
        fill_circle(canvas, cx, cy, radius, outline)
        fill_circle(canvas, cx, cy, radius - t, fill)
    else:
        _, x, y, w, h = shape
        radius = min(w, h) * 0.3
        fill_round_rect(canvas, x, y, w, h, radius, outline)
        fill_round_rect(canvas, x + t, y + t, w - 2 * t, h - 2 * t, max(radius - t, 0), fill)
        cx = x + w / 2
        cy = y + h / 2
    if label:
        room = 2 * (radius - t) if shape[0] == "circle" else w - 2 * t
        if canvas.text_width(label, "small") > room * 0.92:
            label = SHORT.get(label, label)
        canvas.text(label, cx, cy, text, "small", "center")


def draw_stick(canvas, center, info, targeted):
    """The stick's deflection; its click is L3/R3 in the top row. A stick the device lacks is grayed out."""
    cx, cy, radius = center
    present = info.get("present") and not info.get("absent")
    ring = TARGET if targeted else (OUTLINE if present else DIM)
    fill_circle(canvas, cx, cy, radius, ring)
    fill_circle(canvas, cx, cy, radius - max(2, radius * 0.07), BODY if not present else KEY)
    if present:
        dot = radius * 0.32
        reach = radius - dot - 3
        dx = max(-1.0, min(1.0, info.get("dx", 0.0)))
        dy = max(-1.0, min(1.0, info.get("dy", 0.0)))
        moved = abs(dx) > 0.15 or abs(dy) > 0.15
        canvas.box(DIM, cx - reach, cy, 2 * reach, 1)
        canvas.box(DIM, cx, cy - reach, 1, 2 * reach)
        fill_circle(canvas, cx + dx * reach, cy + dy * reach, dot, ON if moved else OUTLINE)


def draw(canvas, area, scene):
    """Draw the whole scene in area = (x, y, w, h)."""
    x, y, w, h = area
    canvas.box(PANEL, x, y, w, h)
    big = canvas.line_height("big")
    normal = canvas.line_height("normal")
    small = canvas.line_height("small")
    top = y + normal * 0.2
    if scene.prompt:
        canvas.text(scene.prompt, x + w / 2, top + normal / 2, scene.prompt_color, "normal", "center")
    if scene.info is not None:
        draw_info(canvas, (x + 12, top + normal * 1.05, w - 24, h - (top - y) - normal * 1.05), scene)
        return None
    rows = max(scene.line_rows, len(scene.lines))
    lines_h = small * (rows + 0.3) if rows else 0
    pic = (x + 6, top + normal * 1.05, w - 12, h - (top - y) - normal * 1.05 - lines_h)
    layout = Layout(*pic)
    u = layout.u
    thick = max(1, int(u * 0.08))
    bx, by, bw, bh = layout.body
    fill_round_rect(canvas, bx, by, bw, bh, 1.5 * u, BODY)
    for slot, shape in layout.rects.items():
        label = None if slot.startswith("DPAD_") else scene.labels.get(slot, slot)
        draw_slot(canvas, shape, label, scene.state.get(slot, "unknown"), scene.target == slot, thick)
    dcx, dcy, arm = layout.dpad_center
    canvas.box(KEY, dcx - arm / 2, dcy - arm / 2, arm, arm)
    for stick, center in layout.stick.items():
        info = scene.sticks.get(stick, {"present": False})
        draw_stick(canvas, center, info, scene.target in (f"{stick}_X", f"{stick}_Y"))
    ly = y + h - lines_h + small * 0.2
    for text, color in scene.lines:
        canvas.text(text, x + 12, ly + small / 2, color, "small", "left")
        ly += small
    if scene.overlay:
        tw = canvas.text_width(scene.overlay, "big") + 2 * big
        ow = min(tw, w - 16)
        oh = big * 2
        canvas.box(PANEL, x + (w - ow) / 2, pic[1] + pic[3] / 2 - oh / 2, ow, oh)
        canvas.box(scene.overlay_color, x + (w - ow) / 2, pic[1] + pic[3] / 2 - oh / 2, ow, 2)
        canvas.text(scene.overlay, x + w / 2, pic[1] + pic[3] / 2, scene.overlay_color, "big", "center")
    return layout


def wrap(canvas, text, width, size="small"):
    """Lines of text no wider than width, broken between words; continuation lines indented."""
    out = []
    line = ""
    for word in text.split(" "):
        trial = f"{line} {word}" if line else word
        if line and canvas.text_width(trial, size) > width:
            out.append(line)
            line = "    " + word
        else:
            line = trial
    out.append(line)
    return out


def draw_info(canvas, area, scene):
    """The device info pane: wrapped lines from scene.info, scrolled by scene.info_scroll rows."""
    x, y, w, h = area
    small = canvas.line_height("small")
    lines = [(part, color) for text, color in scene.info for part in wrap(canvas, text, w)]
    rows = max(1, int(h // small))
    if len(lines) > rows:
        rows -= 1  # the last row says what is below
    scene.info_max = max(0, len(lines) - rows)
    start = min(scene.info_scroll, scene.info_max)
    ly = y + small / 2
    for text, color in lines[start:start + rows]:
        canvas.text(text, x, ly, color, "small", "left")
        ly += small
    if len(lines) > start + rows:
        canvas.text(f"... {len(lines) - start - rows} more lines (D-pad down)", x, ly, DIM, "small", "left")


class RecordingCanvas:
    """A canvas that only counts and records (host tests, and sizing without a screen)."""

    def __init__(self, char_w=9, line_h=20):
        self.boxes = 0
        self.texts = []
        self.char_w = char_w
        self.line_h = line_h

    def box(self, color, x, y, w, h):
        self.boxes += 1

    def text(self, text, x, y, color, size, align):
        self.texts.append((text, color, size))

    def text_width(self, text, size):
        return len(text) * self.char_w * {"big": 1.4, "normal": 1.15}.get(size, 1)

    def line_height(self, size):
        return self.line_h * {"big": 1.4, "normal": 1.15}.get(size, 1)
