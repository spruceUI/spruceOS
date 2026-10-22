"""What every RA transport shares: RA's hosts, the app's User-Agent and the response type.

Imports neither ``http.client`` nor ``ssl``, so the ROM identification helper's curl requests
load no TLS code from Python (0.45 s on a Mini, .agents/device.md).
"""

from __future__ import annotations

from dataclasses import dataclass, field

import cheevos

API_HOST = "retroachievements.org"
API_V2_HOST = "api.retroachievements.org"  # the JSON:API (events' award tiers)
MEDIA_HOST = "media.retroachievements.org"
STATIC_HOST = "static.retroachievements.org"  # the site's own art (site award badges)
# RA's fixed hosts, the only ones that may fall back to HTTP when TLS fails.
RA_HOSTS = frozenset({API_HOST, API_V2_HOST, MEDIA_HOST, STATIC_HOST})


def default_user_agent(platform: str) -> str:
    """Return the User-Agent RA sees, e.g. ``"Cheevos/0.1.0 (SpruceOS; MiyooMini)"``.

    Args:
        platform: Spruce platform name.

    Returns:
        The User-Agent string.
    """
    return f"Cheevos/{cheevos.__version__} (SpruceOS; {platform})"


@dataclass(frozen=True, slots=True)
class Response:
    """An HTTP response, fully read.

    Attributes:
        status: HTTP status code.
        headers: Response headers with lower-cased names.
        body: Response body.
    """

    status: int
    headers: dict[str, str] = field(default_factory=dict)
    body: bytes = b""
