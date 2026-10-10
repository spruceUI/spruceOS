"""Per-glyph font fallback helpers (SDL-free, safe for unit tests)."""

from typing import Callable, List, NamedTuple


class Run(NamedTuple):
    """One same-font stretch of text: which font renders it + the chars."""
    is_fallback: bool
    segment: str


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
