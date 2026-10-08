"""Check RA reachability through the same HTTPS/HTTP transport used for syncing."""

from __future__ import annotations

import logging
from typing import Protocol

from cheevos.core.ra_client.transport import API_HOST, HttpTransport, Response

logger = logging.getLogger(__name__)


class HeadTransport(Protocol):
    """A transport able to probe a host and release its connection."""

    def head(self, host: str, path: str, headers: dict[str, str]) -> Response:
        """Return the HTTP response to a HEAD request."""
        ...

    def close(self) -> None:
        """Close the probe connection."""
        ...


def is_online(
    *, host: str = API_HOST, timeout: float = 3.0, transport: HeadTransport | None = None
) -> bool:
    """Probe RA with HEAD, also updating app time from its Date header.

    Any answer counts, including HTTP errors: the point is reachability. Only failures to
    connect count as offline. TLS failures use the same HTTP fallback as sync requests.

    Args:
        host: Host to probe.
        timeout: Seconds to wait.
        transport: Replacement transport for tests; otherwise create and close one.

    Returns:
        ``True`` if the host answered.
    """
    probe = transport or HttpTransport(timeout=timeout)
    try:
        probe.head(host, "/", {})
    except Exception as exc:  # noqa: BLE001 — any failure means "offline", by design
        logger.info("RA unreachable: %s", exc)
        return False
    else:
        return True
    finally:
        if transport is None:
            probe.close()
