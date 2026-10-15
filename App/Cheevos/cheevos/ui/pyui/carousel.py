"""The awards carousel: PyUI's animated horizontal carousel with the selection's details.

PyUI keeps the navigation and the animation: the selected award is larger and centred, its
neighbours shrink towards the edges, and moves slide them. Room is kept under the images for
two centred lines about the selection (title, then its description and date), RA's award
frames are drawn around the images' actual bounds, and only the images on screen (and the
next few) are asked for, so downloads follow the selection (.agents/pyui.md, "Carousel").
Short collections draw each award once instead of PyUI's repeated tiles.
"""

from __future__ import annotations

import functools
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any

from cheevos.ui.pyui import image_frames, visible_images
from cheevos.ui.pyui.image_frames import Frame
from cheevos.ui.pyui.primitives import (
    Align,
    Text,
    fit_text,
    fit_with_tail,
    line_height,
    screen_size,
    text,
)
from cheevos.ui.pyui.visible_images import ImageDemand, demanding

FIVE_TILES = 5  # a centred selection with two neighbours on each side
SMALL_TILES = 3  # fewer awards than five, or a portrait screen: one neighbour on each side
_GAP = 16  # at 640x480: around the images and above the details
_ENTRY = "#"  # separates an image path from its entry in the paths PyUI hands back
_AHEAD = 2  # images queued beyond the visible tiles on each side, for the next moves
# The selection's share of the width: five tiles, three, and three on a portrait screen
# (PyUI sizes the images by width; a tall screen has height to spare).
_SHARE_FIVE, _SHARE_THREE, _SHARE_PORTRAIT = 40, 50, 60


def create(title: str, entries: Sequence[Any], selected: int, scale: float) -> Any:  # noqa: ANN401 — PyUI view
    """Create the carousel for PyUI entries carrying ``MenuItem`` values.

    Args:
        title: Top-bar text.
        entries: PyUI entries (see ``views._entries``); ``frame``, ``description`` and
            ``tail`` are used.
        selected: Initially selected index.
        scale: The theme's size against its 640x480 design.

    Returns:
        The view (a PyUI ``CarouselView``).
    """
    return _view_class()(title, list(entries), selected, _Painter(measure(scale)))


@dataclass(frozen=True, slots=True)
class Geometry:
    """Where the images and the details go.

    Attributes:
        width: Screen width.
        portrait: The screen is taller than wide.
        gap: Space around the images and above the details.
        image_y: The images' vertical centre.
        image_height: The room the images have, top to bottom.
        details_y: Top of the first details line.
        title_line: Height of the first details line.
    """

    width: int
    portrait: bool
    gap: int
    image_y: int
    image_height: int
    details_y: int
    title_line: int

    @property
    def text_width(self) -> int:
        """Room for a details line."""
        return max(self.width - 2 * self.gap, 1)


def layout(
    width: int, height: int, bars: tuple[int, int], lines: tuple[int, int], scale: float
) -> Geometry:
    """Keep two lines of details above the bottom bar, and centre the images above them.

    Args:
        width: Screen width.
        height: Screen height.
        bars: Top and bottom bar heights.
        lines: Line heights of the title and body fonts.
        scale: The theme's size against its 640x480 design.

    Returns:
        The geometry.
    """
    top, bottom = bars
    gap = round(_GAP * scale)
    details_y = height - bottom - lines[0] - lines[1] - gap
    return Geometry(
        width=width,
        portrait=height > width,
        gap=gap,
        image_y=(top + details_y - gap) // 2,
        image_height=max(details_y - top - 2 * gap, 1),
        details_y=details_y,
        title_line=lines[0],
    )


def measure(scale: float) -> Geometry:
    """Lay the carousel out for this screen and theme.

    Args:
        scale: The theme's size against its 640x480 design.

    Returns:
        The geometry.
    """
    from display.display import Display

    width, height = screen_size()
    bars = int(Display.get_top_bar_height()), int(Display.get_bottom_bar_height())
    return layout(width, height, bars, (line_height(Text.TITLE), line_height(Text.BODY)), scale)


def columns(count: int, *, portrait: bool) -> tuple[int, int]:
    """Return how many tiles the carousel shows, and the selection's share of the width.

    Args:
        count: Awards in the collection.
        portrait: The screen is taller than wide.

    Returns:
        ``(tiles, percent)``.
    """
    if portrait:
        return SMALL_TILES, _SHARE_PORTRAIT
    return (FIVE_TILES, _SHARE_FIVE) if count >= FIVE_TILES else (SMALL_TILES, _SHARE_THREE)


class _Painter:
    """Draws what the carousel adds to PyUI's: details, image frames, the images it needs.

    The view is PyUI's carousel: ``options`` (repeated for short collections),
    ``options_length`` (the real count), ``selected`` and the visible options. PyUI hands each
    entry's ``image_path`` back to :meth:`image`, so that path names the entry, not only its
    image: several awards share a fallback image but have different frames.

    Args:
        geometry: The layout.
    """

    def __init__(self, geometry: Geometry) -> None:
        self.geometry = geometry
        self._last_selected = -1
        self._drawn: dict[str, tuple[str, Frame | None]] = {}  # entry's key: image, frame
        self._fitted: tuple[int, str, str] = (-1, "", "")

    def details(self, view: Any) -> None:  # noqa: ANN401 — PyUI view
        """Draw the selection's title, then its description and date, centred.

        Args:
            view: The carousel.
        """
        geometry, (index, title, detail) = self.geometry, self._fitted
        if index != view.selected:
            item = view.options[view.selected].get_value()
            title = fit_text(item.title, Text.TITLE, geometry.text_width)
            detail = fit_with_tail(item.description, item.tail, Text.BODY, geometry.text_width)
            self._fitted = (view.selected, title, detail)
        centre = geometry.width // 2
        text(title, centre, geometry.details_y, Text.TITLE, Align.TOP_CENTER)
        y = geometry.details_y + geometry.title_line
        text(detail, centre, y, Text.BODY, Align.TOP_CENTER)

    def images(self, view: Any) -> None:  # noqa: ANN401 — PyUI view
        """Resolve the shown and outgoing images every frame, and queue the next ones.

        Args:
            view: The carousel.
        """
        if view.selected != self._last_selected:
            visible_images.new_window()  # downloads still waiting were for the old neighbours
            self._last_selected = view.selected
        visible, _selected = view.get_visible_options()
        self._drawn = {}
        for entry in [*visible, *(view.prev_visible_options or [])]:
            path = entry.get_icon()
            key = None if path is None else f"{path}{_ENTRY}{id(entry)}"
            entry.image_path = entry.image_path_selected = key
            if key is not None:
                self._drawn[key] = (path, entry.get_value().frame)
        count, reach = len(view.options), view.cols // 2
        with demanding(ImageDemand.NEXT):
            for step in range(reach + 1, reach + _AHEAD + 1):
                for index in (view.selected + step, view.selected - step):
                    view.options[index % count].get_icon()

    def image(self, path: str | None, x: int, width: float, resize_type: object) -> None:
        """Fit an image above the details, centred at ``x``, and frame its drawn bounds.

        Args:
            path: The entry's key from :meth:`images` (or an image file PyUI found itself).
            x: Its centre.
            width: The room PyUI gives it.
            resize_type: PyUI's resize type.
        """
        from display.display import Display
        from display.render_mode import RenderMode

        geometry = self.geometry
        path, frame = self._drawn.get(path, (path, None)) if path is not None else (None, None)
        drawn = Display.render_image(
            path,
            x,
            geometry.image_y,
            RenderMode.MIDDLE_CENTER_ALIGNED,
            max(round(width), 1),
            geometry.image_height,
            resize_type,
        )
        drawn_width, drawn_height = int(drawn[0]), int(drawn[1])
        if frame is not None and drawn_width and drawn_height:
            left, top = int(x - drawn_width // 2), geometry.image_y - drawn_height // 2
            image_frames.fill(frame, (left, top, drawn_width, drawn_height))


@functools.cache
def _view_class() -> type:
    """Define the view class once PyUI can be imported.

    Returns:
        A ``CarouselView`` subclass drawn with a :class:`_Painter`.
    """
    from controller.controller_inputs import ControllerInput
    from display.display import Display
    from views.carousel_view import CarouselView
    from views.selection import Selection

    shoulders = (ControllerInput.L1, ControllerInput.R1)

    class AwardsCarousel(CarouselView):
        """PyUI's carousel between the bars and the selection's details.

        Args:
            title: Top-bar text.
            entries: PyUI entries carrying ``MenuItem`` values.
            selected: Initially selected index.
            painter: Draws the details and frames.
        """

        def __init__(
            self, title: str, entries: list[Any], selected: int, painter: _Painter
        ) -> None:
            self.painter = painter
            tiles, share = columns(len(entries), portrait=painter.geometry.portrait)
            super().__init__(
                top_bar_text=title,
                options=entries,
                cols=tiles,
                selected_index=selected,
                show_grid_text=False,
                set_top_bar_text_to_selection=False,
                set_bottom_bar_text_to_selection=False,
                selected_entry_width_percent=share,
                shrink_further_away=tiles == FIVE_TILES,
                sides_hang_off_edge=False,
                x_pad=painter.geometry.gap,
            )
            # Awards have no useful alphabetic index, even sorted by title.
            self.options_are_sorted = False

        def get_selection(self, select_controller_inputs: list[Any] | None = None) -> Any:  # noqa: ANN401 — PyUI's
            """Page with L1/R1 on themes with tabs too (PyUI hands those to the caller there).

            Args:
                select_controller_inputs: Inputs that end the selection.

            Returns:
                PyUI's selection; no input after paging.
            """
            accepted = select_controller_inputs or [ControllerInput.A]
            selection = super().get_selection(accepted)
            pressed = selection.get_input()
            if pressed not in shoulders or pressed in accepted:
                return selection
            self.skip_next_animation = True
            step = -self.cols if pressed == ControllerInput.L1 else self.cols
            self.adjust_selected(step, skip_by_letter=False)
            return Selection(self.get_selected_option(), None, self.selected)

        def _clear(self) -> None:
            """Draw the theme and the details before each steady or animated frame."""
            Display.clear(self.top_bar_text)
            self.painter.images(self)
            self.painter.details(self)
            if self.options_length < SMALL_TILES:
                self.skip_next_animation = True  # nothing to slide

        def render_images_horizontal(
            self,
            iterable: list[tuple[int, Any]],
            x_offsets: list[int],
            widths: list[int],
            render_selected_only: bool,  # noqa: FBT001 — PyUI's positional signature
        ) -> None:
            """Draw short collections once each, the selection in the centre."""
            if self.options_length < SMALL_TILES:
                middle = len(iterable) // 2
                # One award: the centre only. Two: the centre and the other one on its right.
                iterable = iterable[middle : middle + self.options_length]
            super().render_images_horizontal(iterable, x_offsets, widths, render_selected_only)

        def animate_transition_horizontal(self) -> None:
            """Clear the last animation frame before PyUI draws the settled carousel on it."""
            super().animate_transition_horizontal()
            # PyUI carries on without clearing, which would double its translucent index.
            self._clear()

        def _render_image(  # noqa: PLR0913, PLR0917 — PyUI's positional signature
            self,
            image_path: str | None,
            x: int,
            y: int,
            render_mode: object,
            target_width: float,
            target_height: int,
            resize_type: object,
        ) -> None:
            """Fit each image above the details (PyUI's y, mode and height don't leave room)."""
            del y, render_mode, target_height
            self.painter.image(image_path, x, target_width, resize_type)

    return AwardsCarousel
