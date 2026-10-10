"""Every on-device path the app reads or writes, derived from one SD-card root.

Nothing else in the code base may hard-code ``/mnt/SDCARD`` (see .agents/code.md). The root comes
from ``CHEEVOS_SDCARD_ROOT`` (the desktop runner points it at ``dev/sdcard``).
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_SDCARD = Path("/mnt/SDCARD")
# tmpfs on devices, by design (.agents/sync-and-storage.md).
DEFAULT_SCRATCH = Path("/tmp/cheevos")  # noqa: S108


@dataclass(frozen=True, slots=True)
class Paths:
    """Resolved locations for one SD card.

    Args:
        sdcard: SD-card root.
        scratch: RAM-backed scratch directory for extracted images.
        platform: Spruce platform name (``$PLATFORM``, e.g. ``"MiyooMini"``).
        retroarch_config_override: ``$SPRUCE_RA_CONFIG`` if set, else ``None``.
    """

    sdcard: Path
    scratch: Path = DEFAULT_SCRATCH
    platform: str = "MiyooMini"
    retroarch_config_override: Path | None = None

    @classmethod
    def from_env(cls) -> Paths:
        """Build paths from the environment (``CHEEVOS_SDCARD_ROOT``, ``PLATFORM``, ...).

        Returns:
            The resolved paths.
        """
        ra_config = os.environ.get("SPRUCE_RA_CONFIG")
        return cls(
            sdcard=Path(os.environ.get("CHEEVOS_SDCARD_ROOT") or DEFAULT_SDCARD),
            scratch=Path(os.environ.get("CHEEVOS_SCRATCH") or DEFAULT_SCRATCH),
            platform=os.environ.get("PLATFORM") or "MiyooMini",
            retroarch_config_override=Path(ra_config) if ra_config else None,
        )

    # --- user data (plain files, survive updates) ---------------------------------------------

    @property
    def user_dir(self) -> Path:
        """``Saves/cheevos``: user data only (API key, settings)."""
        return self.sdcard / "Saves" / "cheevos"

    @property
    def api_key_file(self) -> Path:
        """The Web API key file."""
        return self.user_dir / "apikey.txt"

    @property
    def settings_file(self) -> Path:
        """The settings JSON."""
        return self.user_dir / "settings.json"

    # --- disposable caches ----------------------------------------------------------------------

    @property
    def app_dir(self) -> Path:
        """``App/Cheevos``: the installed app."""
        return self.sdcard / "App" / "Cheevos"

    @property
    def cache_dir(self) -> Path:
        """``Saves/cheevos/cache``: everything here may be deleted at any time."""
        return self.user_dir / "cache"

    @property
    def data_db(self) -> Path:
        """RA data cache database."""
        return self.cache_dir / "data.db"

    @property
    def media_db(self) -> Path:
        """Image cache database."""
        return self.cache_dir / "media.db"

    @property
    def media_scratch(self) -> Path:
        """Extracted images for the current screen (RAM-backed on devices)."""
        return self.scratch / "media"

    @property
    def scaled_scratch(self) -> Path:
        """Pixel-art copies enlarged for full-screen viewing (RAM-backed on devices)."""
        return self.scratch / "scaled"

    @property
    def log_file(self) -> Path:
        """App log, following Spruce's ``Saves/spruce/<app>-$PLATFORM.log`` convention."""
        return self.sdcard / "Saves" / "spruce" / f"cheevos-{self.platform}.log"

    # --- read-only Spruce / RetroArch / proxy files ---------------------------------------------

    @property
    def spruce_config(self) -> Path:
        """Spruce's settings (RA username in "RetroAchievements Settings")."""
        return self.sdcard / "Saves" / "spruce" / "spruce-config.json"

    @property
    def retroarch_config(self) -> Path:
        """The live RetroArch config for this platform."""
        if self.retroarch_config_override is not None:
            return self.retroarch_config_override
        return self.sdcard / "Saves" / "ra-configs" / f"retroarch-{self.platform}.cfg"

    @property
    def default_screenshot_dir(self) -> Path:
        """Where Spruce's RetroArch saves screenshots unless its config says otherwise."""
        return self.sdcard / "Saves" / "screenshots"

    @property
    def proxy_data_dir(self) -> Path:
        """RAOfflineProxy's data directory (read-only for us)."""
        return self.sdcard / "App" / "RAOfflineProxy" / "data"
