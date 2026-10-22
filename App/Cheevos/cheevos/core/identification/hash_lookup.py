"""Resolve hash candidates to an RA game: RAOfflineProxy's cache first, then RA.

The proxy's database is only ever opened read-only (``mode=ro`` creates nothing), and the
helper writes nothing to it: answers RA gives are kept only in the helper's path cache.
Candidates are tried in the hasher's order; a later cached match never skips an earlier
candidate, since different hashing rules can identify different games.

RA's lookup is the RetroArch API's ``r=gameid``, which RA answers without credentials (RAWeb's
``GetGameIdFromHashAction`` is not an authenticated action, and rcheevos sends none), so
identification needs no sign-in, token or Web API key. Only an explicit successful zero
``GameID`` is a miss; anything malformed, refused or unreachable is an error and isn't cached
(.agents/integration.md).
"""

from __future__ import annotations

import json
import logging
import re
import sqlite3
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Protocol
from urllib.parse import urlencode

from cheevos.core.errors import NetworkError
from cheevos.core.identification.result import (
    AUTH,
    HASH,
    NETWORK,
    OFFLINE,
    RATE_LIMITED,
    RESPONSE,
    Identification,
    IdentificationError,
    positive_game_id,
    real_game_id,
)
from cheevos.core.ra_client.common import API_HOST

if TYPE_CHECKING:
    from cheevos.core.ra_client.transport import Transport

logger = logging.getLogger(__name__)

GAMEID_PREFIX = "gameid:"
ACHIEVEMENTSETS_PREFIX = "achievementsets:"
MISS_TTL_MS = 7 * 24 * 60 * 60 * 1000  # the proxy's GAMEID_MISS_TTL_MS
REQUIRED_COLUMNS = frozenset({"cacheKey", "responseBody", "cachedAt"})
REQUEST_INTERVAL = 0.3  # the proxy's own spacing between RA requests
_HASH_PATTERN = re.compile(r"[0-9a-f]{32}")
_HTTP_OK = 200
_HTTP_TOO_MANY = 429
_HTTP_SERVER_ERROR = 500
_AUTH_STATUSES = frozenset({401, 403})
_UNSUPPORTED_CLIENT = "unsupported_client"


@dataclass(frozen=True, slots=True)
class CachedAnswer:
    """What the proxy's cache says about one hash.

    Attributes:
        game_id: The cached game, if any.
        miss: RA said "no game" less than a week ago.
    """

    game_id: int | None = None
    miss: bool = False


UNKNOWN = CachedAnswer()


def _load_object(body: str | bytes) -> dict[str, object] | None:
    """Decode a JSON object, or ``None`` for anything else."""
    try:
        data = json.loads(body)
    except (ValueError, TypeError):  # JSONDecodeError and UnicodeDecodeError are ValueErrors
        return None
    return data if isinstance(data, dict) else None


def is_confirmed_miss(payload: dict[str, object]) -> bool:
    """Recognise RA's explicit "no game for this hash" answer: ``Success`` and a zero ID."""
    game_id = payload.get("GameID")
    return payload.get("Success") is True and type(game_id) is int and game_id == 0


class ProxyHashCache:
    """Read-only lookups in RAOfflineProxy's ``api_cache``.

    A missing, locked or unfamiliar database reads as "nothing cached", so the lookup carries
    on with RA.

    Args:
        database: ``App/RAOfflineProxy/data/proxy.sqlite3``.
        now: Epoch seconds, for the age of cached misses.
    """

    def __init__(self, database: Path, *, now: Callable[[], float]) -> None:
        self._database = database
        self._now = now
        self._connection: sqlite3.Connection | None = None
        self._unusable = False

    def lookup(self, hash_value: str) -> CachedAnswer:
        """Return the proxy's cached answer for a hash, mirroring its own lookup order.

        A ``gameid:<hash>`` match, then an ``achievementsets:<hash>:<user>`` response's game,
        then a recent ``gameid:`` miss.

        Args:
            hash_value: Lower-case hex MD5.

        Returns:
            The cached answer, or :data:`UNKNOWN`.
        """
        connection = self._connect()
        if connection is None:
            return UNKNOWN
        try:
            return self._answer(connection, hash_value)
        except sqlite3.Error as exc:
            logger.warning("Cannot read RAOfflineProxy's cache: %s", exc)
            self.close()
            self._unusable = True
            return UNKNOWN

    def _answer(self, connection: sqlite3.Connection, hash_value: str) -> CachedAnswer:
        """Query both cache formats for one hash."""
        row = connection.execute(
            "SELECT responseBody, cachedAt FROM api_cache WHERE cacheKey = ? LIMIT 1",
            (GAMEID_PREFIX + hash_value,),
        ).fetchone()
        body, cached_at = row if row is not None else (None, None)
        gameid = _load_object(body) if isinstance(body, str) else None
        if gameid is not None:
            game_id = positive_game_id(gameid.get("GameID"))
            if game_id is not None:
                return CachedAnswer(game_id=game_id)
        # GLOB uses the cacheKey index; a hex hash has no wildcard characters.
        sets = connection.execute(
            "SELECT responseBody FROM api_cache WHERE cacheKey GLOB ? LIMIT 1",
            (f"{ACHIEVEMENTSETS_PREFIX}{hash_value}:*",),
        ).fetchone()
        payload = _load_object(sets[0]) if sets and isinstance(sets[0], str) else None
        game_id = positive_game_id(payload.get("GameId")) if payload is not None else None
        if game_id is not None:
            return CachedAnswer(game_id=game_id)
        if gameid is not None and is_confirmed_miss(gameid) and self._recent(cached_at):
            return CachedAnswer(miss=True)
        return UNKNOWN

    def _recent(self, cached_at: object) -> bool:
        """Check a cached miss's age (milliseconds); a clock that went back counts as stale."""
        if type(cached_at) is not int:
            return False
        return 0 <= self._now() * 1000 - cached_at < MISS_TTL_MS

    def _connect(self) -> sqlite3.Connection | None:
        """Open the database read-only on first use, checking the columns we read."""
        if self._connection is not None or self._unusable:
            return self._connection
        self._unusable = True  # until proven otherwise
        if not self._database.is_file():
            return None
        try:
            uri = self._database.resolve().as_uri() + "?mode=ro"  # mode=ro never creates files
            connection = sqlite3.connect(uri, uri=True, timeout=1.0)
        except sqlite3.Error as exc:
            logger.warning("Cannot open RAOfflineProxy's cache: %s", exc)
            return None
        try:
            columns = {row[1] for row in connection.execute("PRAGMA table_info(api_cache)")}
        except sqlite3.Error as exc:
            logger.warning("Cannot read RAOfflineProxy's cache: %s", exc)
            connection.close()
            return None
        if not columns >= REQUIRED_COLUMNS:
            logger.warning("RAOfflineProxy's cache schema changed; asking RA instead")
            connection.close()
            return None
        self._connection = connection
        self._unusable = False
        return connection

    def close(self) -> None:
        """Close the connection, if open."""
        if self._connection is not None:
            self._connection.close()
            self._connection = None


def parse_gameid_response(status: int, body: bytes) -> int | None:
    """Interpret RA's ``r=gameid`` answer.

    Args:
        status: HTTP status.
        body: Response body.

    Returns:
        The game ID, or ``None`` for RA's explicit "no game".

    Raises:
        IdentificationError: Any other answer (never cached as a miss).
    """
    payload = _load_object(body)
    code = str(payload.get("Code", "")) if payload is not None else ""
    if status == _HTTP_TOO_MANY:
        raise IdentificationError(RATE_LIMITED, "HTTP 429")
    if status in _AUTH_STATUSES and code != _UNSUPPORTED_CLIENT:
        raise IdentificationError(AUTH, f"HTTP {status} {code}".rstrip())
    if status >= _HTTP_SERVER_ERROR or (status != _HTTP_OK and payload is None):
        raise IdentificationError(NETWORK, f"HTTP {status}")
    if payload is None or status != _HTTP_OK or payload.get("Success") is False:
        raise IdentificationError(RESPONSE, f"HTTP {status} {code}".rstrip())
    game_id = positive_game_id(payload.get("GameID"))
    if game_id is not None:
        return game_id
    if is_confirmed_miss(payload):
        return None
    raise IdentificationError(RESPONSE, "no usable GameID")


class RaHashLookup:
    """Ask RA which game a hash belongs to, spacing requests like the proxy does.

    Args:
        transport: HTTPS transport with RA's HTTP fallback.
        user_agent: The app's User-Agent.
        clock: Monotonic clock.
        sleep: Sleep function.
    """

    def __init__(
        self,
        transport: Transport,
        user_agent: str,
        *,
        clock: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        self._transport = transport
        self._headers = {"User-Agent": user_agent, "Accept": "application/json"}
        self._clock = clock
        self._sleep = sleep
        self._last: float | None = None

    def game_id(self, hash_value: str) -> int | None:
        """Return the hash's game, or ``None`` when RA has none.

        Args:
            hash_value: Lower-case hex MD5.

        Returns:
            The game ID, or ``None``.

        Raises:
            IdentificationError: RA couldn't be reached or gave an unusable answer.
        """
        if self._last is not None:
            self._sleep(max(0.0, self._last + REQUEST_INTERVAL - self._clock()))
        path = "/dorequest.php?" + urlencode({"r": "gameid", "m": hash_value})
        try:
            response = self._transport.get(API_HOST, path, self._headers)
        except NetworkError as exc:
            raise IdentificationError(OFFLINE, str(exc)) from exc
        finally:
            self._last = self._clock()
        return parse_gameid_response(response.status, response.body)


class HashResolver(Protocol):
    """Where hashes the proxy hasn't cached are looked up (:class:`RaHashLookup`)."""

    def game_id(self, hash_value: str) -> int | None:
        """Return the hash's game, or ``None`` when there is none."""
        ...


def resolve(
    candidates: tuple[str, ...], cache: ProxyHashCache, ra: Callable[[], HashResolver]
) -> Identification:
    """Find the first candidate with a game, from the proxy's cache or RA.

    Args:
        candidates: Hash candidates in the hasher's order.
        cache: The proxy's cache.
        ra: Creates the RA lookup on first need, so cached answers load no network code.

    Returns:
        A match, or a confirmed miss when every candidate has no game.

    Raises:
        IdentificationError: A candidate couldn't be resolved.
    """
    resolver: HashResolver | None = None
    for candidate in candidates:
        hash_value = candidate.strip().lower()
        if not _HASH_PATTERN.fullmatch(hash_value):
            raise IdentificationError(HASH, f"hasher returned {candidate!r}")
        answer = cache.lookup(hash_value)
        if answer.game_id is not None:
            return _match(answer.game_id, "RAOfflineProxy's cache")
        if answer.miss:
            continue
        resolver = resolver or ra()
        game_id = resolver.game_id(hash_value)
        if game_id is not None:
            return _match(game_id, "RA")
    return Identification.no_match()


def _match(game_id: int, source: str) -> Identification:
    """Build the match for RA's answer, decoding a virtual ID to its game."""
    real, compatibility = real_game_id(game_id)
    logger.info("Matched game %d from %s (hash: %s)", real, source, compatibility or "compatible")
    return Identification.matched(real)
