"""RetroAchievements Web API client (``/API/API_*.php`` with the user's Web API key).

Only the Web API is used; the Connect API (``dorequest.php``) belongs to emulators and the
offline proxy.
"""

from cheevos.core.ra_client.client import RaClient, default_user_agent
from cheevos.core.ra_client.redact import RedactingFilter, install_redaction
from cheevos.core.ra_client.transport import (
    API_HOST,
    MEDIA_HOST,
    FixtureTransport,
    HttpTransport,
    Response,
    Transport,
)

__all__ = [
    "API_HOST",
    "MEDIA_HOST",
    "FixtureTransport",
    "HttpTransport",
    "RaClient",
    "RedactingFilter",
    "Response",
    "Transport",
    "default_user_agent",
    "install_redaction",
]
