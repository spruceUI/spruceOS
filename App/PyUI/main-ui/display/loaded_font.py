try:
    import sdl2.sdlttf as _sdlttf
except Exception:
    _sdlttf = None

from display.font_fallback import split_fallback_runs

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
    # Non-BMP skips the 16-bit probe and falls closed below: on old
    # libs it always takes the fallback, which is the safe direction.
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
    """Primary font plus an ordered list of fallback fonts.

    fonts[0] is always the primary handle; fonts[1:] are fallbacks in
    preference order. Run.font_index addresses into this list.
    """

    def __init__(self, font, line_height, font_path,
                 fallback_fonts=None, fallback_paths=None, sdlttf=None):
        self.font = font
        self.line_height = line_height
        self.font_path = font_path
        self.fallback_fonts = list(fallback_fonts) if fallback_fonts else []
        self.fallback_paths = list(fallback_paths) if fallback_paths else []
        self.fonts = [font] + self.fallback_fonts
        self._sdlttf = sdlttf if sdlttf is not None else _sdlttf
        self._glyph_cache = {}
        self._font_index_cache = {}

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
        """Font handle that renders a run. Never raises.

        Negative index addresses the last font in the pair (the last
        fallback when one is loaded, else the primary handle);
        out-of-range index falls back to the primary handle.
        """
        try:
            index = int(font_index)
        except Exception:
            return self.font
        if not self.fonts:
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

    def has_glyph(self, codepoint):
        cp = self._to_codepoint(codepoint)
        if cp not in self._glyph_cache:
            self._store_bounded(
                self._glyph_cache, cp,
                _probe_glyph(self.font, cp, self._sdlttf,
                             fallback_available=self.has_fallback()))
        return self._glyph_cache[cp]

    def font_index_for(self, codepoint):
        """Index of the first font providing codepoint. Never raises.

        Probes primary first, then fallbacks in order. When no font
        provides the glyph, returns the last fallback index (fail-closed
        toward the fallback side); with a single font, returns 0.
        """
        cp = self._to_codepoint(codepoint)
        if cp not in self._font_index_cache:
            index = self._first_provider(cp)
            self._store_bounded(self._font_index_cache, cp, index)
        return self._font_index_cache[cp]

    def _first_provider(self, cp):
        for index, handle in enumerate(self.fonts):
            if _probe_glyph(handle, cp, self._sdlttf,
                            fallback_available=self.has_fallback()):
                return index
        return len(self.fonts) - 1 if self.fonts else 0

    def cache_key(self, purpose):
        """Text-texture cache identity: purpose + the ordered font paths."""
        return (purpose, self.font_path, tuple(self.fallback_paths))
