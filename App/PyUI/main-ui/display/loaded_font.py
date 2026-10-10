try:
    import sdl2.sdlttf as _sdlttf
except Exception:
    _sdlttf = None


def _probe_glyph(font_ptr, codepoint, sdlttf=None):
    """Return True if font_ptr provides codepoint. Never raises."""
    try:
        mod = sdlttf if sdlttf is not None else _sdlttf
        if mod is None or font_ptr is None:
            return True
        probe32 = getattr(mod, "TTF_GlyphIsProvided32", None)
        if callable(probe32):
            return bool(probe32(font_ptr, int(codepoint)))
        probe16 = getattr(mod, "TTF_GlyphIsProvided", None)
        if callable(probe16) and int(codepoint) <= 0xFFFF:
            return bool(probe16(font_ptr, int(codepoint)))
        return True
    except Exception:
        return True


class LoadedFont:
    def __init__(self, font, line_height, font_path,
                 fallback_font=None, fallback_path=None, sdlttf=None):
        self.font = font
        self.line_height = line_height
        self.font_path = font_path
        self.fallback_font = fallback_font
        self.fallback_path = fallback_path
        self._sdlttf = sdlttf if sdlttf is not None else _sdlttf
        self._glyph_cache = {}
        self._fallback_glyph_cache = {}

    @staticmethod
    def _to_codepoint(value):
        if isinstance(value, str):
            return ord(value[0]) if value else 0
        return int(value)

    def has_glyph(self, codepoint):
        cp = self._to_codepoint(codepoint)
        if cp not in self._glyph_cache:
            self._glyph_cache[cp] = _probe_glyph(self.font, cp, self._sdlttf)
        return self._glyph_cache[cp]

    def fallback_has_glyph(self, codepoint):
        cp = self._to_codepoint(codepoint)
        if cp not in self._fallback_glyph_cache:
            self._fallback_glyph_cache[cp] = _probe_glyph(
                self.fallback_font, cp, self._sdlttf)
        return self._fallback_glyph_cache[cp]
