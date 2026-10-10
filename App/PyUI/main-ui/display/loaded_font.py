try:
    import sdl2.sdlttf as _sdlttf
except Exception:
    _sdlttf = None

from display.font_fallback import Run, split_fallback_runs


# Upper bound for each per-font glyph probe cache. Eviction is a plain
# clear: probe results cost one SDL call per codepoint to rebuild, so a
# full clear is cheap and keeps the render hot path branch-free.
# Caches live on the LoadedFont object, so dropping the object on theme
# switch (Display.deinit_fonts) drops its caches too: no leak across
# theme switches, and a fresh LoadedFont always starts empty.
GLYPH_CACHE_LIMIT = 4096


def _probe_glyph(font_ptr, codepoint, sdlttf=None, fallback_available=False):
    """Return True if font_ptr provides codepoint. Never raises.

    Tries the 32-bit probe first, then falls through to the 16-bit
    probe (present since SDL_ttf 2.0.12) when the 32-bit call is
    missing or raises -- e.g. pysdl2 binds TTF_GlyphIsProvided32 but
    the loaded lib is older than 2.0.18, which raises RuntimeError on
    call. All PyUI UI glyphs are BMP, so the 16-bit probe covers them.

    Fail-closed toward the fallback: a None handle or probes that all
    fail report missing (False) so the fallback font can rescue the
    glyph. The only fail-open case is a completely missing SDL probe
    API with no usable fallback, where True preserves the old
    single-font behaviour (nothing else could render the glyph anyway).
    """
    if font_ptr is None:
        return False
    mod = sdlttf if sdlttf is not None else _sdlttf
    if mod is None:
        return False if fallback_available else True
    cp = int(codepoint)
    tried = False
    probe32 = getattr(mod, "TTF_GlyphIsProvided32", None)
    if callable(probe32):
        tried = True
        try:
            return bool(probe32(font_ptr, cp))
        except Exception:
            pass  # old lib: fall through to the 16-bit probe below
    if cp <= 0xFFFF:
        probe16 = getattr(mod, "TTF_GlyphIsProvided", None)
        if callable(probe16):
            tried = True
            try:
                return bool(probe16(font_ptr, cp))
            except Exception:
                pass
    if tried:
        # A probe existed but every call failed: report missing so the
        # fallback font gets its chance (or the primary renders anyway
        # when there is no fallback to switch to).
        return False
    return False if fallback_available else True


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

    @staticmethod
    def _store_bounded(cache, cp, value):
        if len(cache) > GLYPH_CACHE_LIMIT:
            cache.clear()
        cache[cp] = value
        return value

    def has_fallback(self):
        return self.fallback_font is not None and self.fallback_font != self.font

    def handle_for(self, use_fallback):
        """Font handle that renders a run: fallback when asked and usable."""
        if use_fallback and self.has_fallback():
            return self.fallback_font
        return self.font

    def split(self, text):
        """Split text into runs served by primary vs fallback (see Run)."""
        return split_fallback_runs(text, self.has_glyph)

    def _probe_cached(self, cache, handle, cp, fallback_available):
        if cp not in cache:
            self._store_bounded(
                cache, cp,
                _probe_glyph(handle, cp, self._sdlttf,
                             fallback_available=fallback_available))
        return cache[cp]

    def has_glyph(self, codepoint):
        cp = self._to_codepoint(codepoint)
        return self._probe_cached(self._glyph_cache, self.font, cp,
                                 self.has_fallback())

    def fallback_has_glyph(self, codepoint):
        cp = self._to_codepoint(codepoint)
        return self._probe_cached(self._fallback_glyph_cache,
                                 self.fallback_font, cp, True)

    def cache_key(self, purpose):
        """Text-texture cache identity: purpose + the font pair paths."""
        return (purpose, self.font_path, self.fallback_path)
