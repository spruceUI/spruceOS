"""Keep PyUI's texture caches within a memory budget.

PyUI keeps a texture for every distinct text and image it draws, and never evicts one. When an
allocation finally fails, it flushes both caches and tries again ("Clearing cache : Out of
memory" in the log). On a Miyoo Mini, textures come from a 21 MB graphics pool (MMA) that the
screen buffers already use more than half of, so paging through a few long achievement lists
ran it dry every half minute, and a screenshot that needed one big block failed to load.

:func:`install` swaps each cache's dictionary for a :class:`TextureLru`, which destroys the
least recently drawn textures beyond a budget measured in screens' worth of pixels (a bigger
screen gets a bigger budget). PyUI's own code is unchanged: it reads and writes ``cache`` as
before.
"""

from __future__ import annotations

import logging
from collections import OrderedDict
from collections.abc import Callable, Iterator, ValuesView
from typing import Any

logger = logging.getLogger(__name__)

TEXT_SCREENS = 2.5  # text textures kept: 2.5 screens of pixels (3 MB at 640x480)
IMAGE_SCREENS = 2.5  # image textures kept, the same
BYTES_PER_PIXEL = 4  # PyUI's textures are 32-bit
_CACHES = (("_text_texture_cache", TEXT_SCREENS), ("_image_texture_cache", IMAGE_SCREENS))


def texture_bytes(entry: Any) -> int:  # noqa: ANN401 — PyUI's cache entry
    """Estimate a cached texture's memory from its size.

    Args:
        entry: A PyUI cache entry (``width``, ``height``, ``texture``).

    Returns:
        Bytes, assuming 32-bit pixels.
    """
    return int(entry.width) * int(entry.height) * BYTES_PER_PIXEL


class TextureLru:
    """The part of a dict PyUI's texture caches use, evicting the least recently used.

    Args:
        budget: Bytes of textures to keep.
        destroy: Frees a texture (``SDL_DestroyTexture``).
    """

    def __init__(self, budget: int, destroy: Callable[[Any], object]) -> None:
        self.budget = budget
        self.used = 0
        self._destroy = destroy
        self._entries: OrderedDict[Any, Any] = OrderedDict()

    def get(self, key: Any, default: Any = None) -> Any:  # noqa: ANN401 — PyUI's keys and entries
        """Return an entry and mark it as just used.

        Args:
            key: Cache key.
            default: Returned when the key is missing.

        Returns:
            The entry, or ``default``.
        """
        entry = self._entries.get(key)
        if entry is None:
            return default
        self._entries.move_to_end(key)
        return entry

    def __setitem__(self, key: Any, entry: Any) -> None:  # noqa: ANN401 — PyUI's keys and entries
        """Store an entry, then evict the oldest ones while over budget (never the new one).

        Args:
            key: Cache key.
            entry: Cache entry.
        """
        old = self._entries.pop(key, None)
        if old is not None:
            self.used -= texture_bytes(old)
            if old.texture is not entry.texture:
                self._destroy(old.texture)
        self._entries[key] = entry
        self.used += texture_bytes(entry)
        while self.used > self.budget and len(self._entries) > 1:
            _, victim = self._entries.popitem(last=False)
            self.used -= texture_bytes(victim)
            self._destroy(victim.texture)

    def values(self) -> ValuesView[Any]:
        """Return the entries (PyUI destroys them all before :meth:`clear`).

        Returns:
            A view of the entries.
        """
        return self._entries.values()

    def clear(self) -> None:
        """Forget every entry; PyUI has already destroyed their textures."""
        self._entries.clear()
        self.used = 0

    def __len__(self) -> int:
        """Return the number of cached textures.

        Returns:
            The count.
        """
        return len(self._entries)

    def __iter__(self) -> Iterator[Any]:
        """Iterate over the keys, oldest first.

        Returns:
            An iterator over the keys.
        """
        return iter(self._entries)


def install(display: Any, screen_width: int, screen_height: int) -> None:  # noqa: ANN401 — PyUI's Display
    """Put PyUI's text and image texture caches on a budget.

    Args:
        display: PyUI's ``Display`` class, initialised.
        screen_width: Screen width in pixels.
        screen_height: Screen height in pixels.
    """
    import sdl2

    screen = screen_width * screen_height * BYTES_PER_PIXEL
    for name, screens in _CACHES:
        cache = getattr(display, name, None)
        entries = getattr(cache, "cache", None)
        if isinstance(entries, TextureLru):
            continue
        if not isinstance(entries, dict):
            logger.warning("PyUI's %s has changed; its textures stay unbounded", name)
            continue
        lru = TextureLru(int(screen * screens), sdl2.SDL_DestroyTexture)
        for key, entry in entries.items():
            lru[key] = entry
        cache.cache = lru  # ty: ignore[invalid-assignment] — PyUI's cache object is untyped
        logger.debug("%s: %d KB budget", name, lru.budget // 1024)
