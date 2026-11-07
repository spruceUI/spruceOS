from __future__ import annotations

"""On-screen keyboard for the Windows menu: text entry with a controller
(proxy port, search, RetroAchievements login, Send Logs details). A physical
keyboard types into it directly. Mixed into WindowsMenuSession."""

import time
from dataclasses import dataclass, field
from typing import Callable

from ..menu_input import (
    BTN_DPAD_DOWN,
    BTN_DPAD_LEFT,
    BTN_DPAD_RIGHT,
    BTN_DPAD_UP,
    BTN_START,
    BTN_TL,
    BTN_TR,
    KEY_DOWN,
    KEY_LEFT,
    KEY_RIGHT,
    KEY_UP,
)
from ..menu_sdl import (
    BACKGROUND_COLOR,
    LEFT_MARGIN,
    PRIMARY_COLOR,
    SECONDARY_TEXT_COLOR,
    SELECTED_COLOR,
    TEXT_COLOR,
)

KEYBOARD_VIEW = "win_keyboard"

SHIFT = "Shift"
SPACE = "Space"
DELETE = "Del"
DONE = "Done"
CANCEL = "Cancel"

TEXT_ROWS = [
    list("1234567890"),
    list("qwertyuiop"),
    list("asdfghjkl@"),
    list("zxcvbnm._-"),
    [SHIFT, SPACE, DELETE, DONE, CANCEL],
]
NUMBER_ROWS = [
    list("123"),
    list("456"),
    list("789"),
    ["0", DELETE],
    [DONE, CANCEL],
]


@dataclass
class KeyboardState:
    title: str
    prompt: str
    value: str
    on_done: Callable[[str], None]
    return_view: str
    secret: bool = False
    numeric: bool = False
    max_length: int = 128
    shifted: bool = False
    row: int = 0
    col: int = 0
    rows: list[list[str]] = field(default_factory=list)


class KeyboardMixin:
    keyboard: KeyboardState | None = None

    def open_keyboard(
        self,
        title: str,
        prompt: str,
        on_done: Callable[[str], None],
        initial: str = "",
        secret: bool = False,
        numeric: bool = False,
        max_length: int = 128,
    ) -> None:
        """on_done gets the text on Done; Cancel returns to the calling view
        without calling it. on_done may change self.view to move on."""
        self.keyboard = KeyboardState(
            title=title,
            prompt=prompt,
            value=initial,
            on_done=on_done,
            return_view=self.view,
            secret=secret,
            numeric=numeric,
            max_length=max_length,
            rows=NUMBER_ROWS if numeric else TEXT_ROWS,
        )
        self.save_view_position(self.view)
        self.view = KEYBOARD_VIEW

    # Input -----------------------------------------------------------------

    def keyboard_move(self, d_row: int, d_col: int) -> None:
        kb = self.keyboard
        kb.row = (kb.row + d_row) % len(kb.rows)
        if d_row:
            # Keep roughly the same horizontal position across rows of different widths.
            kb.col = min(kb.col, len(kb.rows[kb.row]) - 1)
        kb.col = (kb.col + d_col) % len(kb.rows[kb.row])

    def keyboard_type(self, text: str) -> None:
        kb = self.keyboard
        if kb.numeric:
            text = "".join(ch for ch in text if ch.isdigit())
        kb.value = (kb.value + text)[: kb.max_length]

    def keyboard_delete(self) -> None:
        self.keyboard.value = self.keyboard.value[:-1]

    def keyboard_close(self, accept: bool) -> None:
        kb = self.keyboard
        self.keyboard = None
        self.view = kb.return_view
        self.restore_view_position(kb.return_view)
        if accept:
            kb.on_done(kb.value)

    def keyboard_press_selected(self) -> None:
        kb = self.keyboard
        key = kb.rows[kb.row][kb.col]
        if key == SHIFT:
            kb.shifted = not kb.shifted
        elif key == SPACE:
            self.keyboard_type(" ")
        elif key == DELETE:
            self.keyboard_delete()
        elif key == DONE:
            self.keyboard_close(accept=True)
        elif key == CANCEL:
            self.keyboard_close(accept=False)
        else:
            self.keyboard_type(key.upper() if kb.shifted else key)

    def keyboard_handle_code(self, key: int) -> None:
        """A gamepad code from read_keys: d-pad moves, A types, B deletes,
        Start is Done, the shoulder buttons toggle Shift."""
        if key in (KEY_UP, BTN_DPAD_UP):
            self.keyboard_move(-1, 0)
        elif key in (KEY_DOWN, BTN_DPAD_DOWN):
            self.keyboard_move(1, 0)
        elif key in (KEY_LEFT, BTN_DPAD_LEFT):
            self.keyboard_move(0, -1)
        elif key in (KEY_RIGHT, BTN_DPAD_RIGHT):
            self.keyboard_move(0, 1)
        elif key in (BTN_TL, BTN_TR):
            self.keyboard.shifted = not self.keyboard.shifted
        elif key == BTN_START:
            self.keyboard_close(accept=True)
        elif self.is_cancel_key(key):
            self.keyboard_delete()
        elif self.is_confirm_key(key):
            self.keyboard_press_selected()

    def keyboard_handle_event(self, event) -> None:
        """A pygame KEYDOWN from a physical keyboard: type straight in."""
        pygame = self.pygame
        if event.key == pygame.K_RETURN:
            self.keyboard_close(accept=True)
        elif event.key == pygame.K_ESCAPE:
            self.keyboard_close(accept=False)
        elif event.key == pygame.K_BACKSPACE:
            self.keyboard_delete()
        elif event.key in (pygame.K_UP, pygame.K_DOWN, pygame.K_LEFT, pygame.K_RIGHT):
            self.keyboard_move(
                {pygame.K_UP: -1, pygame.K_DOWN: 1}.get(event.key, 0),
                {pygame.K_LEFT: -1, pygame.K_RIGHT: 1}.get(event.key, 0),
            )
        elif getattr(event, "unicode", "") and event.unicode.isprintable():
            self.keyboard_type(event.unicode)

    # Drawing ---------------------------------------------------------------

    def render_keyboard(self) -> None:
        kb = self.keyboard
        surface = self.surface
        surface.fill(BACKGROUND_COLOR)

        title = self.title_font.render(kb.title, False, PRIMARY_COLOR)
        title_rect = title.get_rect(topleft=(LEFT_MARGIN, max(36, self.height // 12)))
        surface.blit(title, title_rect)
        bottom = self.render_wrapped_status(kb.prompt, title_rect.bottom + 20)

        # The text field, with a blinking caret.
        shown = "*" * len(kb.value) if kb.secret else kb.value
        caret = "_" if int(time.monotonic() * 2) % 2 == 0 else " "
        field_text = self.item_font.render(shown + caret, False, TEXT_COLOR)
        field_rect = self.pygame.Rect(
            LEFT_MARGIN, bottom + 24, self.width - 2 * LEFT_MARGIN, field_text.get_height() + 20
        )
        self.pygame.draw.rect(surface, SECONDARY_TEXT_COLOR, field_rect, width=2)
        surface.blit(field_text, (field_rect.x + 12, field_rect.y + 10))

        # The key grid: equal-width cells per row, centred.
        top = field_rect.bottom + 32
        self.key_rects = []  # for mouse clicks (mouse.py)
        key_height = self.item_font.get_height() + 24
        usable = self.width - 2 * LEFT_MARGIN
        widest = max(len(row) for row in kb.rows)
        for row_index, row in enumerate(kb.rows):
            cell = usable // widest if len(row) == widest else usable // len(row)
            row_left = LEFT_MARGIN + (usable - cell * len(row)) // 2
            y = top + row_index * (key_height + 10)
            for col_index, key in enumerate(row):
                rect = self.pygame.Rect(row_left + col_index * cell + 4, y, cell - 8, key_height)
                self.key_rects.append((row_index, col_index, rect))
                selected = row_index == kb.row and col_index == kb.col
                active_shift = key == SHIFT and kb.shifted
                self.pygame.draw.rect(
                    surface,
                    SELECTED_COLOR if selected else (PRIMARY_COLOR if active_shift else SECONDARY_TEXT_COLOR),
                    rect,
                    width=0 if selected else 2,
                    border_radius=6,
                )
                label = key.upper() if kb.shifted and len(key) == 1 else key
                text = self.item_font.render(label, False, BACKGROUND_COLOR if selected else TEXT_COLOR)
                surface.blit(text, text.get_rect(center=rect.center))

        hint = "A: type   B: delete   LB/RB: shift   Start: done   (or use a keyboard)"
        if kb.numeric:
            hint = "A: type   B: delete   Start: done   (or use a keyboard)"
        if self.message is not None and time.monotonic() < self.message[1]:
            hint = self.message[0]
        overlay = self.status_font.render(hint, False, SELECTED_COLOR)
        surface.blit(overlay, overlay.get_rect(topleft=(LEFT_MARGIN, self.height - 56)))
        self.pygame.display.flip()
