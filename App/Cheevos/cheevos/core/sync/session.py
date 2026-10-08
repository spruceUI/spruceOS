"""Wire real collaborators for a sync: credentials, HTTPS client, caches, on-device matching."""

from __future__ import annotations

import logging
import threading
from dataclasses import dataclass

from cheevos.core.credentials import read_api_key, read_username
from cheevos.core.errors import ConfigError
from cheevos.core.local_games import on_device_game_ids
from cheevos.core.proxy import ProxyReader
from cheevos.core.ra_client.client import RaClient, default_user_agent
from cheevos.core.ra_client.pacer import Pacer
from cheevos.core.ra_client.transport import HttpTransport, Transport
from cheevos.core.storage.data_cache import DataCache
from cheevos.core.storage.media_cache import MediaCache
from cheevos.core.sync.engine import SyncDeps
from cheevos.platform.paths import Paths

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class Credentials:
    """Who to sync as.

    Attributes:
        username: RA username.
        api_key: RA Web API key.
    """

    username: str
    api_key: str


def load_credentials(paths: Paths) -> Credentials:
    """Read the username (Spruce or RetroArch settings) and the API key file.

    Args:
        paths: Device paths.

    Returns:
        The credentials.

    Raises:
        ConfigError: If either is missing.
    """
    username = read_username(paths)
    if not username:
        raise ConfigError("no RetroAchievements username in Spruce or RetroArch settings")
    api_key = read_api_key(paths)
    if not api_key:
        raise ConfigError(f"no Web API key in {paths.api_key_file}")
    return Credentials(username, api_key)


def make_client(
    paths: Paths,
    credentials: Credentials,
    transport: Transport,
    *,
    pacer: Pacer,
    cancel: threading.Event | None = None,
) -> RaClient:
    """Create an RA client with the app's user agent.

    Args:
        paths: Device paths (for the platform name in the user agent).
        credentials: Account.
        transport: HTTP transport.
        pacer: The pacer shared by every client of this key.
        cancel: Interrupts the client's waits when set (a sync's cancel event).

    Returns:
        The client.
    """
    return RaClient(
        credentials.username,
        credentials.api_key,
        transport,
        user_agent=default_user_agent(paths.platform),
        pacer=pacer,
        cancel=cancel,
    )


def open_sync_deps(
    paths: Paths,
    credentials: Credentials,
    transport: Transport | None = None,
    *,
    pacer: Pacer | None = None,
    cancel: threading.Event | None = None,
) -> SyncDeps:
    """Create sync collaborators; call on the thread that will run the sync.

    Args:
        paths: Device paths.
        credentials: Account to sync.
        transport: HTTP transport; a new keep-alive HTTPS transport when ``None``.
        pacer: The pacer shared by every client of this key; a new one when ``None``.
        cancel: The sync's cancel event: interrupts the client's waits.

    Returns:
        Collaborators whose ``close`` releases connections and sockets.
    """
    transport = transport or HttpTransport()
    client = make_client(
        paths, credentials, transport, pacer=pacer if pacer is not None else Pacer(), cancel=cancel
    )
    data = DataCache.open(paths.data_db, credentials.username)
    media = MediaCache.open(paths.media_db, paths.media_scratch)
    proxy = ProxyReader(paths)

    def close() -> None:
        """Release caches and connections."""
        data.close()
        media.close()
        close_transport = getattr(transport, "close", None)
        if close_transport is not None:
            close_transport()

    return SyncDeps(
        client=client,
        data=data,
        media=media,
        on_device=lambda: on_device_game_ids(paths, proxy),
        close=close,
    )
