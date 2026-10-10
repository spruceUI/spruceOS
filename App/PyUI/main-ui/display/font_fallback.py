"""Per-glyph font fallback helpers (SDL-free, safe for unit tests)."""


def split_fallback_runs(text, has_glyph):
    """Split text into consecutive same-font runs.

    Args:
        text: string to split.
        has_glyph: callable taking a codepoint int, True when the primary
            font provides the glyph.

    Returns:
        List of (use_fallback, segment) tuples with consecutive
        same-decision chars grouped. Empty text -> [].
    """
    runs = []
    if not text:
        return runs
    for ch in text:
        try:
            missing = not has_glyph(ord(ch))
        except Exception:
            missing = False
        if runs and runs[-1][0] == missing:
            runs[-1] = (missing, runs[-1][1] + ch)
        else:
            runs.append((missing, ch))
    return runs
