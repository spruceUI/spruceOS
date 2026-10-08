"""Keep-alive HTTPS with an HTTP fallback for TLS failures, or recorded fixtures."""

from __future__ import annotations

import http.client
import json
import logging
import os
import ssl
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol
from urllib.parse import parse_qsl, urlsplit

from cheevos.core.clock import ServerClock, network_clock
from cheevos.core.errors import NetworkError

logger = logging.getLogger(__name__)

API_HOST = "retroachievements.org"
MEDIA_HOST = "media.retroachievements.org"
DEFAULT_TIMEOUT = 15.0

# A kept-alive connection the server closed between requests: reconnect and retry once.
_DROPPED: tuple[type[BaseException], ...] = (
    http.client.RemoteDisconnected,
    BrokenPipeError,
    ConnectionResetError,
)
# Query parameters that carry credentials; never recorded, never matched on.
_CREDENTIAL_PARAMS = frozenset({"y", "u"})


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


class Transport(Protocol):
    """Something that can perform a GET request."""

    def get(self, host: str, path: str, headers: dict[str, str]) -> Response:
        """Perform ``GET https://<host><path>``.

        Args:
            host: Host name.
            path: Path including the query string.
            headers: Request headers.

        Returns:
            The response (any status).
        """
        ...


class Connection(Protocol):
    """The subset of ``http.client.HTTPSConnection`` the transport uses."""

    def request(self, method: str, url: str, *, headers: dict[str, str]) -> None:
        """Send a request."""
        ...

    def getresponse(self) -> http.client.HTTPResponse:
        """Read the response status line and headers."""
        ...

    def close(self) -> None:
        """Close the socket."""
        ...


ConnectionFactory = Callable[[str, float, ssl.SSLContext], Connection]
PlainConnectionFactory = Callable[[str, float], Connection]


def _http_connection(host: str, timeout: float) -> Connection:
    """Open a plain HTTP connection lazily, for RA's TLS fallback."""
    return http.client.HTTPConnection(host, timeout=timeout)


def _https_connection(host: str, timeout: float, context: ssl.SSLContext) -> Connection:
    """Open a real HTTPS connection (lazily: the socket connects on first request).

    Args:
        host: Host name.
        timeout: Socket timeout in seconds.
        context: TLS context.

    Returns:
        The connection.
    """
    return http.client.HTTPSConnection(host, timeout=timeout, context=context)


def default_ssl_context() -> ssl.SSLContext:
    """Return a verifying TLS context, using ``$SSL_CERT_FILE`` when set (Spruce's CA bundle).

    Returns:
        The TLS context.
    """
    return ssl.create_default_context(cafile=os.environ.get("SSL_CERT_FILE") or None)


class HttpTransport:
    """Prefer verified HTTPS; retry RA hosts over HTTP if TLS is unavailable.

    Opening a TLS connection costs ~1 s on a Miyoo Mini; reused connections answer in ~100 ms
    (measured on the Mini), so connections are kept and reused.

    Args:
        timeout: Socket timeout in seconds.
        connection_factory: Creates connections; tests inject fakes.
        ssl_context: TLS context; defaults to :func:`default_ssl_context`.
        http_connection_factory: Creates fallback HTTP connections.
        server_clock: App clock updated from the API host's Date headers.
    """

    def __init__(
        self,
        *,
        timeout: float = DEFAULT_TIMEOUT,
        connection_factory: ConnectionFactory = _https_connection,
        ssl_context: ssl.SSLContext | None = None,
        http_connection_factory: PlainConnectionFactory = _http_connection,
        server_clock: ServerClock = network_clock,
    ) -> None:
        self._timeout = timeout
        self._factory = connection_factory
        self._context = ssl_context
        self._http_factory = http_connection_factory
        self._clock = server_clock
        self._plain_hosts: set[str] = set()
        self._connections: dict[str, Connection] = {}

    def get(self, host: str, path: str, headers: dict[str, str]) -> Response:
        """Perform a GET, reconnecting once if the kept-alive connection was dropped.

        Args:
            host: Host name.
            path: Path including the query string.
            headers: Request headers.

        Returns:
            The response.

        Raises:
            NetworkError: The request failed (DNS, TLS, timeout, connection loss, bad HTTP).
        """
        return self._request("GET", host, path, headers)

    def head(self, host: str, path: str, headers: dict[str, str]) -> Response:
        """Probe a host without downloading a body, using the same TLS fallback as GET."""
        return self._request("HEAD", host, path, headers)

    def _request(self, method: str, host: str, path: str, headers: dict[str, str]) -> Response:
        """Retry dropped connections and TLS failures, never downgrading other failures."""
        try:
            try:
                return self._retry_dropped(method, host, path, headers)
            except ssl.SSLError as exc:
                if host not in (API_HOST, MEDIA_HOST) or host in self._plain_hosts:
                    raise
                logger.warning("TLS unavailable for %s (%s); using HTTP", host, type(exc).__name__)
                self._discard(host)
                self._plain_hosts.add(host)
                return self._retry_dropped(method, host, path, headers)
        except (OSError, http.client.HTTPException) as exc:
            self._discard(host)
            raise NetworkError(f"{host}: {type(exc).__name__}: {exc}") from exc

    def _retry_dropped(
        self, method: str, host: str, path: str, headers: dict[str, str]
    ) -> Response:
        """Reconnect once when the server dropped a kept-alive connection."""
        try:
            return self._send(method, host, path, headers)
        except _DROPPED as exc:
            logger.info("Connection to %s dropped (%s); reconnecting", host, type(exc).__name__)
            self._discard(host)
            return self._send(method, host, path, headers)

    def _send(self, method: str, host: str, path: str, headers: dict[str, str]) -> Response:
        """Send one request on the host's connection and read the whole response.

        Args:
            method: GET or HEAD.
            host: Host name.
            path: Path including the query string.
            headers: Request headers.

        Returns:
            The response.
        """
        connection = self._connection(host)
        connection.request(method, path, headers=headers)
        response = connection.getresponse()
        body = response.read()
        names = {name.lower(): value for name, value in response.getheaders()}
        if host == API_HOST:
            self._clock.observe_date(names.get("date"))
        return Response(status=response.status, headers=names, body=body)

    def _connection(self, host: str) -> Connection:
        """Return the cached connection for ``host``, creating it if needed.

        Args:
            host: Host name.

        Returns:
            The connection.
        """
        connection = self._connections.get(host)
        if connection is None:
            if host in self._plain_hosts:
                connection = self._http_factory(host, self._timeout)
            else:
                if self._context is None:
                    try:
                        self._context = default_ssl_context()
                    except OSError as exc:
                        raise ssl.SSLError("Could not load the TLS certificate bundle") from exc
                connection = self._factory(host, self._timeout, self._context)
            self._connections[host] = connection
        return connection

    def _discard(self, host: str) -> None:
        """Close and forget the connection for ``host``.

        Args:
            host: Host name.
        """
        connection = self._connections.pop(host, None)
        if connection is not None:
            try:
                connection.close()
            except OSError:
                logger.debug("Ignoring error while closing connection to %s", host)

    def close(self) -> None:
        """Close all connections."""
        for host in list(self._connections):
            self._discard(host)


@dataclass(frozen=True, slots=True)
class _Recorded:
    """One recorded API response from ``manifest.json``.

    Attributes:
        method: Endpoint name, e.g. ``"API_GetUserSummary"``.
        params: Recorded query parameters (without credentials), as strings.
        file: Response body file.
    """

    method: str
    params: dict[str, str]
    file: Path


class FixtureTransport:
    """Serve recorded responses (``scripts/record_fixtures.py`` output); never uses the network.

    API requests match a recorded response by endpoint and parameters (credentials ignored).
    When nothing matches exactly and the endpoint was recorded only once, that response is
    served: endpoint-wide options such as page sizes then don't need to match the recording.
    Media paths are served from ``media_dir`` laid out like the media host
    (``<media_dir>/Badge/123.png``).

    Args:
        fixtures_dir: Directory with ``manifest.json`` and the recorded JSON files.
        media_dir: Optional directory mirroring the media host's paths.
    """

    def __init__(self, fixtures_dir: Path, media_dir: Path | None = None) -> None:
        manifest = json.loads((fixtures_dir / "manifest.json").read_text(encoding="utf-8"))
        self._recorded = [
            _Recorded(
                method=entry["method"],
                params={key: str(value) for key, value in entry.get("params", {}).items()},
                file=fixtures_dir / entry["file"],
            )
            for entry in manifest["requests"]
        ]
        self._media_dir = media_dir
        self.calls: list[tuple[str, dict[str, str]]] = []

    def get(self, host: str, path: str, headers: dict[str, str]) -> Response:
        """Answer a request from the recordings.

        Args:
            host: Host name (only used to tell API and media requests apart).
            path: Path including the query string.
            headers: Ignored.

        Returns:
            The recorded response, or a 404 response.
        """
        parts = urlsplit(path)
        if host != MEDIA_HOST and parts.path.startswith("/API/"):
            method = parts.path.removeprefix("/API/").removesuffix(".php")
            params = {
                key: value for key, value in parse_qsl(parts.query) if key not in _CREDENTIAL_PARAMS
            }
            self.calls.append((method, params))
            return self._api_response(method, params)
        self.calls.append((parts.path, {}))
        return self._media_response(parts.path)

    def _api_response(self, method: str, params: dict[str, str]) -> Response:
        """Find the recorded response for an API request.

        Args:
            method: Endpoint name.
            params: Request parameters without credentials.

        Returns:
            The recorded body with status 200, or a 404 response.
        """
        candidates = [entry for entry in self._recorded if entry.method == method]
        match = next((entry for entry in candidates if entry.params == params), None)
        if match is None and len(candidates) == 1:
            match = candidates[0]
        if match is None:
            return Response(status=404, body=b'{"message":"Not recorded"}')
        return Response(
            status=200,
            headers={"content-type": "application/json"},
            body=match.file.read_bytes(),
        )

    def _media_response(self, path: str) -> Response:
        """Serve a media file from ``media_dir``.

        Args:
            path: Media path, e.g. ``"/Badge/123.png"``.

        Returns:
            The file with status 200, or a 404 response.
        """
        if self._media_dir is None:
            return Response(status=404)
        candidate = (self._media_dir / path.lstrip("/")).resolve()
        if not candidate.is_relative_to(self._media_dir.resolve()) or not candidate.is_file():
            return Response(status=404)
        return Response(
            status=200, headers={"content-type": "image/png"}, body=candidate.read_bytes()
        )
