"""Per-glyph font fallback helpers (SDL-free, safe for unit tests)."""

import os
from typing import Callable, List, NamedTuple


# Stock candidates in preference order (Brick has /mnt/SDCARD).
DEFAULT_STOCK_CANDIDATES = (
    "/mnt/SDCARD/SPRUCE/nunwen.ttf",
    "/mnt/SDCARD/spruce/SPRUCE/nunwen.ttf",
    "/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf",
    "/mnt/SDCARD/spruce/Themes/SPRUCE/nunwen.ttf",
)


class Run(NamedTuple):
    """One same-font stretch of text: which font renders it + the chars.

    font_index 0 is the primary font, 1+ are fallback fonts in order.
    """
    font_index: int
    segment: str


def is_single_primary(runs: List[Run]) -> bool:
    """True when the whole text is one run the primary font covers."""
    return len(runs) == 1 and runs[0].font_index == 0


def split_fallback_runs(text: str, font_for: Callable[[int], int]) -> List[Run]:
    """Group text into consecutive same-font runs. Empty text -> [].

    font_for maps a codepoint to a font index (negative = last font).
    """
    runs: List[Run] = []
    if not text:
        return runs
    for ch in text:
        try:
            font_index = int(font_for(ord(ch)))
        except Exception:
            # Failed probe routes to the last font, never silent tofu.
            font_index = -1
        if runs and runs[-1].font_index == font_index:
            runs[-1] = Run(font_index, runs[-1].segment + ch)
        else:
            runs.append(Run(font_index, ch))
    return runs


def _log_fallback_branch(msg):
    try:
        from utils.logger import PyUiLogger
        logger = PyUiLogger.get_logger()
        if logger is not None:
            logger.info(msg)
    except Exception:
        pass


def resolve_fallback_paths(env_path=None,
                           stock_candidates=DEFAULT_STOCK_CANDIDATES):
    """Ordered fallback font paths: $PYUI_FALLBACK_FONT first, then stock.

    Skips missing files; empty means single-font rendering. Never raises.
    """
    paths = []
    if env_path is None:
        env_path = os.environ.get("PYUI_FALLBACK_FONT", "")
    if env_path and os.path.exists(env_path):
        _log_fallback_branch(f"Fallback font branch: env override {env_path}")
        paths.append(env_path)

    for candidate in stock_candidates:
        if candidate and candidate not in paths and os.path.exists(candidate):
            _log_fallback_branch(f"Fallback font branch: stock {candidate}")
            paths.append(candidate)

    return paths
