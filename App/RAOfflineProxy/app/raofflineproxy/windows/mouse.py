from __future__ import annotations

"""Mouse support for the Windows menu, which the handheld menu never needed:
hover highlights a row, left click opens it, right click goes back and the
wheel scrolls. On the on-screen keyboard a click presses the key. Mixed into
WindowsMenuSession."""

from .keyboard import KEYBOARD_VIEW


class MouseMixin:
    # Where the shared render drew the list this frame: the first status block
    # it renders ends just above the items (see render_wrapped_status).
    items_start_y: int | None = None
    capture_items_start: bool = False
    key_rects: list[tuple[int, int, object]] = []

    def render(self) -> None:
        self.capture_items_start = True
        super().render()

    def render_wrapped_status(self, text: str, top_y: int) -> int:
        bottom = super().render_wrapped_status(text, top_y)
        if self.capture_items_start:
            self.capture_items_start = False
            self.items_start_y = bottom + 34  # the gap MenuSdlSession.render leaves
        return bottom

    def item_at(self, position) -> int | None:
        """The index of the list row under the pointer, if any."""
        if self.items_start_y is None:
            return None
        x, y = position
        if x > self.width // 2 and self.view == "main":
            return None  # the status panel
        items = self.current_labels()
        if not items:
            return None
        start, gap = self.items_start_y, self.item_gap()
        positions = self.item_positions(items, start, gap)
        visible_offset, visible = self.visible_items(items, positions, start)
        scroll = positions[visible_offset] - start if visible else 0
        for index, _label in visible:
            top = positions[index] - scroll
            if top - gap // 4 <= y < top + gap - gap // 4:
                return index
        return None

    def key_at(self, position) -> tuple[int, int] | None:
        for row, col, rect in self.key_rects:
            if rect.collidepoint(position):
                return row, col
        return None

    def handle_mouse_event(self, event) -> bool:
        """True when the event was a mouse event (handled or ignored)."""
        pygame = self.pygame
        if event.type == pygame.MOUSEWHEEL:
            if self.view != KEYBOARD_VIEW:
                self.navigate(-event.y)
            return True
        if event.type == pygame.MOUSEMOTION:
            if self.view == KEYBOARD_VIEW:
                hit = self.key_at(event.pos)
                if hit is not None and self.keyboard is not None:
                    self.keyboard.row, self.keyboard.col = hit
            else:
                index = self.item_at(event.pos)
                if index is not None:
                    self.selected_index = index
            return True
        if event.type == pygame.MOUSEBUTTONDOWN:
            if event.button == 3:
                if self.view == KEYBOARD_VIEW:
                    self.keyboard_close(accept=False)
                else:
                    self.go_back()
            elif event.button == 1:
                if self.view == KEYBOARD_VIEW:
                    hit = self.key_at(event.pos)
                    if hit is not None and self.keyboard is not None:
                        self.keyboard.row, self.keyboard.col = hit
                        self.keyboard_press_selected()
                else:
                    index = self.item_at(event.pos)
                    if index is not None:
                        self.selected_index = index
                        self.activate_selected()
            return True
        return event.type in (pygame.MOUSEBUTTONUP,)
