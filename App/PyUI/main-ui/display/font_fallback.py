"""Per-glyph font fallback helpers (SDL-free, safe for unit tests)."""

import os
from typing import Callable, List, NamedTuple


class Run(NamedTuple):
    """One same-font stretch of text: which font renders it + the chars."""
    is_fallback: bool
    segment: str


def is_single_primary(runs: List[Run]) -> bool:
    """True when the whole text is one run the primary font covers."""
    return len(runs) == 1 and not runs[0].is_fallback


def split_fallback_runs(text: str, has_glyph: Callable[[int], bool]) -> List[Run]:
    """Split text into consecutive same-font runs.

    Args:
        text: string to split.
        has_glyph: callable taking a codepoint int, True when the primary
            font provides the glyph.

    Returns:
        Runs with consecutive same-decision chars grouped.
        Empty text -> [].
    """
    runs: List[Run] = []
    if not text:
        return runs
    for ch in text:
        try:
            use_fallback = not has_glyph(ord(ch))
        except Exception:
            # A failing probe must not silently render tofu from the
            # primary: route the char to the fallback side instead.
            use_fallback = True
        if runs and runs[-1].is_fallback == use_fallback:
            runs[-1] = Run(use_fallback, runs[-1].segment + ch)
        else:
            runs.append(Run(use_fallback, ch))
    return runs


# Device stock fallback candidates (Brick always has /mnt/SDCARD).
DEFAULT_STOCK_CANDIDATES = (
    "/mnt/SDCARD/SPRUCE/nunwen.ttf",
    "/mnt/SDCARD/spruce/SPRUCE/nunwen.ttf",
    "/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf",
    "/mnt/SDCARD/spruce/Themes/SPRUCE/nunwen.ttf",
)


def _log_fallback_branch(msg):
    try:
        from utils.logger import PyUiLogger
        logger = PyUiLogger.get_logger()
        if logger is not None:
            logger.info(msg)
    except Exception:
        pass


def resolve_fallback_path(env_path=None, stock_candidates=None):
    """Resolve the render-layer fallback font path (Theme owns primary only).

    1. Explicit env_path, else $PYUI_FALLBACK_FONT, when pointing to an
       existing file.
    2. First existing entry of stock_candidates (default device paths).
    3. Otherwise None: caller renders single-font (no per-glyph fallback).

    Never raises for missing files; logs only on a hit, stays silent on
    a miss so Display can warn once at the single call site.
    """
    if env_path is None:
        env_path = os.environ.get("PYUI_FALLBACK_FONT", "")
    if env_path and os.path.exists(env_path):
        _log_fallback_branch(f"Fallback font branch: env override {env_path}")
        return env_path

    if stock_candidates is None:
        stock_candidates = DEFAULT_STOCK_CANDIDATES
    for candidate in stock_candidates:
        if candidate and os.path.exists(candidate):
            _log_fallback_branch(f"Fallback font branch: stock {candidate}")
            return candidate

    return None
