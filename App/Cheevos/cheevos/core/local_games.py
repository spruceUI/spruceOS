"""Which RA games are on this SD card, using matches Spruce already made (.agents/integration.md).

v1 hashes no ROMs. It reads RAOfflineProxy's cached game IDs.
"""

from __future__ import annotations

from cheevos.core.models import LocalGame
from cheevos.core.proxy import ProxyReader

SOURCE_PROXY = "raofflineproxy"


def local_games(proxy: ProxyReader) -> list[LocalGame]:
    """Return RA games known to be on this device.

    Args:
        proxy: Reader for RAOfflineProxy's cached game IDs.

    Returns:
        Proxy-cached games (without a ROM path), ordered by game ID.
    """
    return [
        LocalGame(game_id=game_id, rom_path="", system="", source=SOURCE_PROXY)
        for game_id in sorted(proxy.cached_game_ids())
    ]


def on_device_game_ids(proxy: ProxyReader) -> set[int]:
    """Return the IDs of RA games known to be on this device.

    Args:
        proxy: Reader for RAOfflineProxy's cached game IDs.

    Returns:
        Game IDs.
    """
    return {game.game_id for game in local_games(proxy)}
