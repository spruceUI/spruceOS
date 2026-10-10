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
            use_fallback = not has_glyph(ord(ch))
        except Exception:
            # A failing probe must not silently render tofu from the
            # primary: route the char to the fallback side instead.
            use_fallback = True
        if runs and runs[-1][0] == use_fallback:
            runs[-1] = (use_fallback, runs[-1][1] + ch)
        else:
            runs.append((use_fallback, ch))
    return runs
