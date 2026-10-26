"""The identification helper's result contract with Spruce (.agents/integration.md).

Every run prints one JSON object: ``{"status":"matched","game_id":1479}``,
``{"status":"no_match"}`` or ``{"status":"error","reason":"offline"}``. Reasons are stable
codes that Spruce turns into messages; details stay in the log.
"""

from __future__ import annotations

from dataclasses import dataclass

from cheevos.core.errors import CheevosError

MATCHED = "matched"
NO_MATCH = "no_match"
ERROR = "error"

# Error reasons. Spruce adds "timeout" (and the "cancelled" status) for its side of the run.
AUTH = "auth"  # RA rejected the request's credentials
OFFLINE = "offline"  # RA couldn't be reached (DNS, connection, TLS, socket timeout)
NETWORK = "network"  # RA answered with a server error or an unexpected HTTP status
RATE_LIMITED = "rate_limited"  # HTTP 429
RESPONSE = "response"  # RA's answer is malformed or an error we don't recognise
FILE = "file"  # the ROM path isn't a readable file
HASH = "hash"  # the ROM's format can't be hashed, or its archive can't be read
DEPENDENCY = "dependency"  # RAOfflineProxy's hasher is missing or incompatible
UNAVAILABLE = "unavailable"  # anything unexpected; the log has the traceback


# RAWeb's VirtualGameIdService: a hash RA hasn't marked compatible resolves to its game's ID
# plus one of these bases, so emulators can warn about it. Checked from the highest.
VIRTUAL_GAME_ID_BASES = (
    (1_200_000_000, "patch required"),
    (1_100_000_000, "untested"),
    (1_000_000_000, "incompatible"),
)


def positive_game_id(value: object) -> int | None:
    """Accept a positive integer game ID, rejecting JSON booleans.

    Args:
        value: Decoded JSON value.

    Returns:
        The game ID, or ``None``.
    """
    return value if isinstance(value, int) and not isinstance(value, bool) and value > 0 else None


def real_game_id(game_id: int) -> tuple[int, str | None]:
    """Decode RA's virtual game ID for a hash it hasn't marked compatible.

    The menu shows the game's progress either way: it doesn't judge whether this ROM version
    can earn achievements (.agents/integration.md).

    Args:
        game_id: A positive game ID from RA or the proxy's cache.

    Returns:
        The game's own ID, and the hash's compatibility when it isn't "compatible".
    """
    for base, compatibility in VIRTUAL_GAME_ID_BASES:
        if game_id > base:
            return game_id - base, compatibility
    return game_id, None


@dataclass(frozen=True, slots=True)
class Identification:
    """One identification outcome.

    Attributes:
        status: ``"matched"``, ``"no_match"`` or ``"error"``.
        game_id: The RA game ID, for a match.
        reason: The error code, for an error.
    """

    status: str
    game_id: int | None = None
    reason: str | None = None

    @classmethod
    def matched(cls, game_id: int) -> Identification:
        """Build a match."""
        return cls(MATCHED, game_id=game_id)

    @classmethod
    def no_match(cls) -> Identification:
        """Build a confirmed miss: RA knows no game for any of the ROM's hashes."""
        return cls(NO_MATCH)

    @classmethod
    def error(cls, reason: str) -> Identification:
        """Build an error with a stable reason code."""
        return cls(ERROR, reason=reason)

    def to_json(self) -> dict[str, object]:
        """Return the JSON object printed for Spruce."""
        if self.status == MATCHED:
            return {"status": MATCHED, "game_id": self.game_id}
        if self.status == NO_MATCH:
            return {"status": NO_MATCH}
        return {"status": ERROR, "reason": self.reason or UNAVAILABLE}

    @classmethod
    def from_cache(cls, data: object) -> Identification | None:
        """Read a cached outcome: only valid matches and confirmed misses are ever cached.

        Args:
            data: A decoded ``result`` object from the path cache.

        Returns:
            The outcome, or ``None`` for anything else.
        """
        if not isinstance(data, dict):
            return None
        if data.get("status") == NO_MATCH:
            return cls.no_match()
        game_id = positive_game_id(data.get("game_id"))
        if data.get("status") == MATCHED and game_id is not None:
            return cls.matched(real_game_id(game_id)[0])  # earlier Spruce builds saved RA's IDs
        return None


class IdentificationError(CheevosError):
    """A lookup failed for a reason Spruce can explain; never cached.

    Args:
        reason: One of this module's reason codes.
        detail: Diagnostic text for the log.
    """

    def __init__(self, reason: str, detail: str = "") -> None:
        super().__init__(f"{reason}: {detail}" if detail else reason)
        self.reason = reason
