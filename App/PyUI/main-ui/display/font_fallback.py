"""Per-glyph font fallback helpers (SDL-free, safe for unit tests)."""

import os
from typing import Callable, List, NamedTuple


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
    """Split text into consecutive same-font runs.

    Args:
        text: string to split.
        font_for: callable taking a codepoint int, returning the index of
            the first font providing the glyph (0 = primary, negative =
            last font in the pair).

    Returns:
        Runs with consecutive same-font chars grouped.
        Empty text -> [].
    """
    runs: List[Run] = []
    if not text:
        return runs
    for ch in text:
        try:
            font_index = int(font_for(ord(ch)))
        except Exception:
            # A failing probe must not silently render tofu from the
            # primary: route the char to the last font in the pair (the
            # last fallback when one is loaded, else the primary).
            font_index = -1
        if runs and runs[-1].font_index == font_index:
            runs[-1] = Run(font_index, runs[-1].segment + ch)
        else:
            runs.append(Run(font_index, ch))
    return runs


# Device stock fallback candidates (Brick always has /mnt/SDCARD).
# Ordered: the resolver collects every existing entry in turn.
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


def resolve_fallback_paths(env_path=None, stock_candidates=None):
    """Resolve the ordered render-layer fallback font paths.

    Theme owns the primary font only; this never reads theme config.

    Order: explicit env_path (else $PYUI_FALLBACK_FONT) when pointing to
    an existing file comes first, then each existing entry of
    stock_candidates (default device paths). Missing files are skipped;
    an empty list means single-font rendering (no per-glyph fallback).

    Never raises for missing files; logs only on a hit, stays silent on
    a miss so Display can warn once at the single call site.
    """
    paths = []
    if env_path is None:
        env_path = os.environ.get("PYUI_FALLBACK_FONT", "")
    if env_path and os.path.exists(env_path):
        _log_fallback_branch(f"Fallback font branch: env override {env_path}")
        paths.append(env_path)

    if stock_candidates is None:
        stock_candidates = DEFAULT_STOCK_CANDIDATES
    for candidate in stock_candidates:
        if candidate and candidate not in paths and os.path.exists(candidate):
            _log_fallback_branch(f"Fallback font branch: stock {candidate}")
            paths.append(candidate)

    return paths
