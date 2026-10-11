try:
    import sdl2.sdlttf as _sdlttf
except Exception:
    _sdlttf = None

from display.font_fallback import split_fallback_runs


def _probe_glyph(font_ptr, codepoint, fallback_available=False):
    """True if font_ptr provides codepoint. Never raises.

    Tries TTF_GlyphIsProvided32 first, then the 16-bit probe: Brick's
    old SDL_ttf raises on the 32-bit call although pysdl2 binds it.
    Fail-closed toward the fallback, except with no probe API and no
    fallback, where True keeps the old single-font behaviour.
    """
    if font_ptr is None:
        return False
    if _sdlttf is None:
        return False if fallback_available else True
    cp = int(codepoint)
    probe32 = getattr(_sdlttf, "TTF_GlyphIsProvided32", None)
    # Non-BMP skips the 16-bit probe; fallback is the safe direction.
    probe16 = getattr(_sdlttf, "TTF_GlyphIsProvided", None) if cp <= 0xFFFF else None
    probes = [p for p in (probe32, probe16) if callable(p)]
    if not probes:
        # Fail open only when no other font could render the glyph.
        return not fallback_available
    for probe in probes:
        try:
            return bool(probe(font_ptr, cp))
        except Exception:
            continue  # old lib: try the next (narrower) probe
    # All probes failed: let the fallback try (or primary renders alone).
    return False


class LoadedFont:
    """Primary font plus an ordered list of fallback fonts.

    fonts[0] is always the primary handle; fonts[1:] are fallbacks in
    preference order. Run.font_index addresses into this list.
    """

    def __init__(self, font, line_height, font_path,
                 fallback_fonts=None, fallback_paths=None):
        self.font = font
        self.line_height = line_height
        self.font_path = font_path
        self.fallback_fonts = list(fallback_fonts) if fallback_fonts else []
        self.fallback_paths = list(fallback_paths) if fallback_paths else []
        self.fonts = [font] + self.fallback_fonts
        self._font_index_cache = {}

    @staticmethod
    def _to_codepoint(value):
        if isinstance(value, str):
            return ord(value[0]) if value else 0
        return int(value)

    def has_fallback(self):
        return any(h is not None and h != self.font
                   for h in self.fallback_fonts)

    def handles_to_close(self):
        """Primary plus each distinct fallback handle, for deinit."""
        handles = []
        seen = set()
        for handle in [self.font] + self.fallback_fonts:
            if handle is None or id(handle) in seen:
                continue
            seen.add(id(handle))
            handles.append(handle)
        return handles

    def handle_for(self, font_index):
        """Font handle rendering a run. Never raises.

        Negative means the last font; out-of-range means primary.
        """
        try:
            index = int(font_index)
        except Exception:
            return self.font
        if index < 0:
            return self.fonts[-1]
        if index >= len(self.fonts):
            return self.font
        handle = self.fonts[index]
        return handle if handle is not None else self.font

    def split(self, text):
        """Split text into runs served by primary vs fallbacks (see Run)."""
        return split_fallback_runs(text, self.font_index_for)

    def font_index_for(self, codepoint):
        """First font index providing codepoint. Never raises.

        No provider: last fallback index, or 0 with a single font.
        """
        cp = self._to_codepoint(codepoint)
        if cp not in self._font_index_cache:
            index = len(self.fonts) - 1 if self.fonts else 0
            for i, handle in enumerate(self.fonts):
                if _probe_glyph(handle, cp,
                                fallback_available=self.has_fallback()):
                    index = i
                    break
            self._font_index_cache[cp] = index
        return self._font_index_cache[cp]

    def cache_key(self, purpose):
        """Text-texture cache identity: purpose + the ordered font paths."""
        return (purpose, self.font_path, tuple(self.fallback_paths))
