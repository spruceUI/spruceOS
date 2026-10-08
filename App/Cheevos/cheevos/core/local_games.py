"""Which RA games are on this SD card, using matches Spruce already made (.agents/integration.md).

v1 hashes no ROMs. It combines PyUI's cheevos cache list (ROM path + RA game ID, written when
the proxy caches a ROM) with RAOfflineProxy's cached game IDs.
"""

from __future__ import annotations

import json
import logging

from cheevos.core.models import LocalGame
from cheevos.core.proxy import ProxyReader
from cheevos.platform.paths import Paths

logger = logging.getLogger(__name__)

SOURCE_PYUI = "pyui-cheevos-cache"
SOURCE_PROXY = "raofflineproxy"


def _pyui_entry(raw: object) -> LocalGame | None:
    """Convert one PyUI cheevos-cache entry.

    Args:
        raw: Decoded entry, expected ``{rom_file_path, game_system_name, display_name,
            game_id}``.

    Returns:
        The local game, or ``None`` for malformed entries.
    """
    if not isinstance(raw, dict):
        return None
    game_id = raw.get("game_id")
    if isinstance(game_id, str) and game_id.strip().isdecimal():  # isdigit() takes "²"
        game_id = int(game_id.strip())
    rom_path = raw.get("rom_file_path")
    if not isinstance(game_id, int) or isinstance(game_id, bool) or game_id <= 0:
        return None
    if not isinstance(rom_path, str) or not rom_path:
        return None
    system = raw.get("game_system_name")
    return LocalGame(
        game_id=game_id,
        rom_path=rom_path,
        system=system if isinstance(system, str) else "",
        source=SOURCE_PYUI,
    )


def _pyui_games(paths: Paths) -> list[LocalGame]:
    """Read PyUI's cheevos cache list.

    Args:
        paths: Resolved paths.

    Returns:
        Valid entries; empty when the file is missing or unreadable.
    """
    try:
        data = json.loads(paths.pyui_cheevos_cache.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return []
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        logger.warning("Cannot read %s: %s", paths.pyui_cheevos_cache, exc)
        return []
    if not isinstance(data, list):
        return []
    return [game for game in map(_pyui_entry, data) if game is not None]


def local_games(paths: Paths, proxy: ProxyReader) -> list[LocalGame]:
    """Return RA games known to be on this device.

    Args:
        paths: Resolved paths.
        proxy: Reader for RAOfflineProxy's cached game IDs.

    Returns:
        PyUI cache entries first, then proxy-cached games not already listed (without a ROM
        path), ordered by game ID within each source.
    """
    games = sorted(_pyui_games(paths), key=lambda game: (game.game_id, game.rom_path))
    covered = {game.game_id for game in games}
    games.extend(
        LocalGame(game_id=game_id, rom_path="", system="", source=SOURCE_PROXY)
        for game_id in sorted(proxy.cached_game_ids() - covered)
    )
    return games


def on_device_game_ids(paths: Paths, proxy: ProxyReader) -> set[int]:
    """Return the IDs of RA games known to be on this device.

    Args:
        paths: Resolved paths.
        proxy: Reader for RAOfflineProxy's cached game IDs.

    Returns:
        Game IDs.
    """
    return {game.game_id for game in local_games(paths, proxy)}
