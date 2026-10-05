"""Pure geometry for the segmented PyUI progress bar.

SDL-free: pure arithmetic only. The caller (ticket 02, the
``TEXT_WITH_PERCENTAGE_BAR`` handler) passes the cell edge length --
typically ``Display.get_line_height(FontPurpose.LIST)`` -- as ``cell_px``
and positions the bar vertically itself (``y`` stays ``None`` here).

Geometry formula (all in pixels, x-axis only)::

    bar_width = round(screen_w * width_ratio)
    x         = round((screen_w - bar_width) / 2)   # centered

For the default ``width_ratio=0.70`` this gives ``x = 15% * screen_w``.

The ``cells`` squares plus ``cells - 1`` gaps must fit exactly::

    cells * cell_size + (cells - 1) * gap == bar_width

Exactly one degree of freedom is solved so the equation holds:

- ``cell_px`` given -> ``gap = (bar_width - cells * cell_px) / (cells - 1)``
- ``gap_px`` given  -> ``cell_size = (bar_width - (cells-1) * gap_px) / cells``
- neither given     -> ``gap = max(1.0, bar_width * _DEFAULT_GAP_RATIO)``,
  then ``cell_size`` from the same equation as the ``gap_px`` case.

``cell_size``/``gap`` are floats so the fit equation holds exactly; the
renderer rounds to ints when calling ``Display.render_box``.

Fill::

    lit_cells = round(clamped_percent / 100 * cells)
"""

from __future__ import annotations

from dataclasses import dataclass


_DEFAULT_WIDTH_RATIO = 0.70
_DEFAULT_GAP_RATIO = 0.008  # gap ~= 0.8% of bar width when unconstrained


@dataclass(frozen=True)
class ProgressBarGeometry:
    """Result of :func:`progress_bar_geometry`."""

    x: int
    y: None  # vertical placement stays with the caller (layout unchanged)
    bar_width: int
    cell_size: float
    gap: float
    lit_cells: int
    cells: int
    percent: float  # clamped to [0, 100]


def progress_bar_geometry(
    screen_w: int,
    percent: float,
    cells: int = 20,
    width_ratio: float = _DEFAULT_WIDTH_RATIO,
    cell_px: int | float | None = None,
    gap_px: int | float | None = None,
) -> ProgressBarGeometry:
    """Compute horizontal geometry for the segmented progress bar."""
    if screen_w <= 0:
        raise ValueError(f"screen_w must be > 0, got {screen_w}")
    if cells < 1:
        raise ValueError(f"cells must be >= 1, got {cells}")
    if not 0 < width_ratio <= 1:
        raise ValueError(f"width_ratio must be in (0, 1], got {width_ratio}")
    if cell_px is not None and cell_px <= 0:
        raise ValueError(f"cell_px must be > 0, got {cell_px}")
    if gap_px is not None and gap_px < 0:
        raise ValueError(f"gap_px must be >= 0, got {gap_px}")

    bar_width = int(round(screen_w * width_ratio))
    x = int(round((screen_w - bar_width) / 2))

    clamped = max(0.0, min(100.0, float(percent)))
    lit_cells = int(round(clamped / 100 * cells))
    lit_cells = max(0, min(cells, lit_cells))

    if cells == 1:
        cell_size = float(cell_px) if cell_px is not None else float(bar_width)
        if cell_size > bar_width:
            raise ValueError(f"cell_px {cell_px} wider than bar_width {bar_width}")
        return ProgressBarGeometry(
            x=x,
            y=None,
            bar_width=bar_width,
            cell_size=cell_size,
            gap=0.0,
            lit_cells=lit_cells,
            cells=cells,
            percent=clamped,
        )

    if cell_px is not None:
        cell_size = float(cell_px)
        if cells * cell_size > bar_width:
            raise ValueError(
                f"cells*cell_px ({cells}*{cell_size}) exceeds bar_width {bar_width}"
            )
        gap = (bar_width - cells * cell_size) / (cells - 1)
    elif gap_px is not None:
        gap = float(gap_px)
        if (cells - 1) * gap > bar_width:
            raise ValueError(
                f"gaps ({cells - 1}*{gap}) exceed bar_width {bar_width}"
            )
        cell_size = (bar_width - (cells - 1) * gap) / cells
    else:
        gap = max(1.0, bar_width * _DEFAULT_GAP_RATIO)
        cell_size = (bar_width - (cells - 1) * gap) / cells

    return ProgressBarGeometry(
        x=x,
        y=None,
        bar_width=bar_width,
        cell_size=cell_size,
        gap=gap,
        lit_cells=lit_cells,
        cells=cells,
        percent=clamped,
    )
