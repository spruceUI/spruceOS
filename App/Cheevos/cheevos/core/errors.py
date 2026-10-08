"""Exception hierarchy: every error the app raises on purpose derives from :class:`CheevosError`."""

from __future__ import annotations


class CheevosError(Exception):
    """Base class for expected, user-reportable failures."""


class AuthError(CheevosError):
    """RA rejected the Web API key (HTTP 401/403, or an "Unauthenticated" payload)."""


class NetworkError(CheevosError):
    """The network is unreachable, a request timed out, or TLS failed."""


class RateLimitedError(CheevosError):
    """RA asked us to slow down (HTTP 429).

    Args:
        retry_after: Seconds to wait before retrying, if RA said.
    """

    def __init__(self, retry_after: float | None = None) -> None:
        super().__init__(
            "RetroAchievements rate limit"
            + (f"; retry after {retry_after:.0f}s" if retry_after is not None else "")
        )
        self.retry_after = retry_after


class RequestCancelledError(CheevosError):
    """A wait before a request was cancelled (the sync was cancelled or the app is exiting)."""


class ApiPayloadError(CheevosError):
    """RA answered with a status or body we cannot interpret."""


class ConfigError(CheevosError):
    """Required configuration is missing (no username or API key)."""
