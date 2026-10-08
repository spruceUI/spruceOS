"""Image paths for screens: cached RA images when available, outline-icon fallbacks otherwise.

Screens ask on every render (PyUI's ``icon_searcher`` runs per frame), so a miss is memoized
until the background fetcher stores something new or the rows on screen change; until then a
missing image costs a set lookup, not a database query. How a miss is requested depends on
what the views are drawing (``ImageDemand``): on screen, the next page, or rows PyUI only
measures.
"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
from typing import Protocol

from cheevos.core.models import Achievement, UserProfile
from cheevos.core.storage.media_cache import MediaCache, avatar_key, badge_key, icon_key
from cheevos.ui.pyui.visible_images import ImageDemand


class ImageFetcher(Protocol):
    """Background downloader interface (implemented by ``LazyMediaFetcher``)."""

    @property
    def version(self) -> int:
        """Changes whenever a newly downloaded image becomes available."""
        ...

    def request(self, key: str, media_path: str, *, later: bool = False) -> None:
        """Ask for ``media_path`` to be downloaded into the cache under ``key``."""
        ...

    def drop_waiting(self) -> None:
        """Forget every request not started yet."""
        ...


class MediaResolver:
    """Resolve image cache keys to files PyUI can load.

    Args:
        media: Image cache (opened on the UI thread).
        icons_dir: Directory of bundled outline icons used as fallbacks.
        fetcher: Background downloader for missing images (a ``LazyMediaFetcher``), or ``None``
            (offline / no key).
        demand: What the views are drawing when they ask (``views.image_demand``).
    """

    def __init__(
        self,
        media: MediaCache,
        icons_dir: Path,
        fetcher: ImageFetcher | None = None,
        demand: Callable[[], ImageDemand] = lambda: ImageDemand.SHOWN,
    ) -> None:
        self._media = media
        self._icons = icons_dir
        self._fetcher = fetcher
        self._demand = demand
        self._asked: set[str] = set()  # missing, requested for the screen
        self._asked_later: set[str] = set()  # missing, requested for the next page
        self._fallbacks: dict[str, Path] = {}  # icon name -> path (asked for on every frame)
        self._seen_version = self.version

    @property
    def version(self) -> int:
        """The fetcher's version (0 without a fetcher); changes when new images arrive."""
        return self._fetcher.version if self._fetcher is not None else 0

    def new_window(self) -> None:
        """Drop downloads still waiting: the rows they were for are no longer on screen."""
        self._asked.clear()
        self._asked_later.clear()
        if self._fetcher is not None:
            self._fetcher.drop_waiting()

    def resolve(self, key: str, media_path: str | None, fallback: str) -> Path:
        """Return the cached image for ``key``, or a fallback icon while it is unavailable.

        A miss on screen is requested ahead of everything waiting, and a miss on the next page
        after it. Rows PyUI only measures get the fallback without a cache lookup: PyUI only
        checks that the row has an image, and extracting every row's cached image churned the
        scratch directory (asked for again when the row is drawn).

        Args:
            key: Image cache key.
            media_path: Path on the media host, or ``None`` if unknown (nothing is fetched).
            fallback: Name of a bundled outline icon, e.g. ``"lock"``.

        Returns:
            A file path PyUI can load.
        """
        missing = self._fallbacks.get(fallback)
        if missing is None:
            missing = self._fallbacks[fallback] = self._icons / f"{fallback}.png"
        demand = self._demand()
        if demand is ImageDemand.MEASURED:  # every row of a new list: keep it cheap
            return missing
        version = self.version
        if version != self._seen_version:
            self._asked.clear()
            self._asked_later.clear()
            self._seen_version = version
        if key in self._asked:
            return missing
        path = self._media.path_for(key)
        if path is not None:
            return path
        later = demand is ImageDemand.NEXT
        asked = self._asked_later if later else self._asked
        if key not in asked:
            asked.add(key)
            if self._fetcher is not None and media_path:
                self._fetcher.request(key, media_path, later=later)
        return missing

    def badge(self, achievement: Achievement, *, unlocked: bool | None = None) -> Path:
        """Return the badge matching the unlock state (colour, or RA's ``_lock`` variant).

        Args:
            achievement: The achievement.
            unlocked: Override the state, e.g. ``True`` for an unlock still waiting in
                RAOfflineProxy's queue (unlocked on the device, not yet on RA).

        Returns:
            The badge, or while it is unavailable a gold trophy (unlocked) or a grey lock
            (locked, like RA's grey locked badges).
        """
        locked = not (achievement.unlocked if unlocked is None else unlocked)
        name = achievement.badge_name
        suffix = "_lock" if locked else ""
        return self.resolve(
            badge_key(name, locked=locked),
            f"/Badge/{name}{suffix}.png",
            "lock-muted" if locked else "trophy",
        )

    def game_icon(self, game_id: int, image_icon: str) -> Path:
        """Return a game's icon.

        Args:
            game_id: RA game ID.
            image_icon: Icon path on the media host (may be empty: nothing is fetched).

        Returns:
            The icon, or a gamepad icon while it is unavailable.
        """
        return self.resolve(icon_key(game_id), image_icon or None, "gamepad")

    def avatar(self, profile: UserProfile | None) -> Path:
        """Return the user's avatar.

        Args:
            profile: Cached profile, or ``None`` before the first sync.

        Returns:
            The avatar, or a user icon while it is unavailable.
        """
        if profile is None:
            return self._icons / "user.png"
        return self.resolve(avatar_key(profile.username), profile.user_pic or None, "user")
