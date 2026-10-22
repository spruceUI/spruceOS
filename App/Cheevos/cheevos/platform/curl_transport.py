"""RA requests through Spruce's curl, for the ROM identification helper (.agents/integration.md).

Spruce ships a static curl for every platform (``spruce/bin`` or ``spruce/bin64``, on its
``PATH``) and makes its own HTTPS requests with it. Each helper run is a new process: asking RA
through Python would first import ``ssl`` and ``http.client`` (0.45 s on a Mini) and resolve
RA's address through the C library (0.3-0.8 s), where curl answers in 0.3-0.6 s, process
included (.agents/device.md). Python's HTTPS stays the fallback whenever curl is missing or
misbehaves, so a broken curl only costs time.
"""

from __future__ import annotations

import logging
import os
import subprocess
from collections.abc import Callable
from typing import TYPE_CHECKING

from cheevos.core.clock import ServerClock, network_clock
from cheevos.core.errors import NetworkError
from cheevos.core.ra_client.common import API_HOST, RA_HOSTS, Response

if TYPE_CHECKING:
    from cheevos.core.ra_client.transport import Transport

logger = logging.getLogger(__name__)

# curl's exit codes (curl(1), "EXIT CODES"). No answer: offline, like Python's socket errors.
NETWORK_FAILURES = frozenset({5, 6, 7, 16, 18, 28, 52, 55, 56, 92})
# TLS failed: RA's hosts retry over HTTP, as the app's transport does. The codes Spruce's
# download_url_to_file (helperFunctions.sh) treats as TLS failures.
TLS_FAILURES = frozenset({35, 51, 58, 59, 60, 77})
# Printed after the body: the status, then the Date header (curl 7.84+; Spruce ships 8.8+).
WRITE_OUT = "\n%{http_code}\n%header{date}"
# How long past its own --max-time a curl that doesn't exit may run before it is killed.
KILL_GRACE = 5.0
_MIN_STATUS, _MAX_STATUS = 100, 599


class _CurlUnusableError(Exception):
    """curl couldn't run, or failed in a way that isn't the network's."""


class _TlsError(Exception):
    """curl couldn't establish TLS."""


class CurlTransport:
    """GET requests through curl, falling back to Python's HTTPS for good once curl fails.

    Matches :class:`~cheevos.core.ra_client.transport.HttpTransport` where the helper relies
    on it: certificates are checked against ``$SSL_CERT_FILE``, a TLS failure on RA's hosts
    retries over HTTP, redirects aren't followed, proxy variables are ignored, and RA's Date
    header sets the app's clock.

    Args:
        curl: The curl executable.
        fallback: Creates Python's transport on first need.
        timeout: Seconds for a whole request.
        server_clock: Receives the API host's Date header.
    """

    def __init__(
        self,
        curl: str,
        fallback: Callable[[], Transport],
        *,
        timeout: float,
        server_clock: ServerClock = network_clock,
    ) -> None:
        self._curl = curl
        self._make_fallback = fallback
        self._fallback: Transport | None = None
        self._timeout = timeout
        self._clock = server_clock
        self._plain_hosts: set[str] = set()

    def get(self, host: str, path: str, headers: dict[str, str]) -> Response:
        """Perform ``GET https://<host><path>``.

        Args:
            host: Host name.
            path: Path including the query string.
            headers: Request headers.

        Returns:
            The response (any status).

        Raises:
            NetworkError: The request failed (DNS, connection, timeout, TLS off RA's hosts).
        """
        if self._fallback is None:
            try:
                return self._get(host, path, headers)
            except _CurlUnusableError as exc:
                logger.warning("curl failed (%s); using Python's HTTPS", exc)
                self._fallback = self._make_fallback()
        return self._fallback.get(host, path, headers)

    def _get(self, host: str, path: str, headers: dict[str, str]) -> Response:
        """Try HTTPS, then HTTP for RA's hosts once TLS has failed."""
        if host not in self._plain_hosts:
            try:
                return self._fetch(f"https://{host}{path}", host, headers)
            except _TlsError as exc:
                if host not in RA_HOSTS:
                    raise NetworkError(f"{host}: {exc}") from exc
                logger.warning("TLS unavailable for %s (%s); using HTTP", host, exc)
                self._plain_hosts.add(host)
        return self._fetch(f"http://{host}{path}", host, headers)

    def _fetch(self, url: str, host: str, headers: dict[str, str]) -> Response:
        """Run curl once and read its answer."""
        # --disable first: no ~/.curlrc may change the request (curl reads it otherwise).
        command = [self._curl, "--disable", "--silent", "--show-error", "--noproxy", "*"]
        command += ["--max-time", f"{self._timeout:g}", "--write-out", WRITE_OUT]
        cafile = os.environ.get("SSL_CERT_FILE")
        if cafile and url.startswith("https:"):
            command += ["--cacert", cafile]
        for name, value in headers.items():
            command += ["--header", f"{name}: {value}"]
        command.append(url)
        try:
            process = subprocess.run(  # noqa: S603 — a fixed executable and argument list
                command,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                timeout=self._timeout + KILL_GRACE,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise NetworkError(f"{host}: curl didn't finish in time") from exc
        except OSError as exc:  # missing, not executable, the wrong architecture
            raise _CurlUnusableError(repr(exc)) from exc
        failure = f"curl {process.returncode}: " + process.stderr.decode(errors="replace").strip()
        if process.returncode in TLS_FAILURES:
            raise _TlsError(failure)
        if process.returncode in NETWORK_FAILURES:
            raise NetworkError(f"{host}: {failure}")
        if process.returncode != 0:
            raise _CurlUnusableError(failure)
        return self._response(host, process.stdout)

    def _response(self, host: str, output: bytes) -> Response:
        """Split the body from the status and Date that ``--write-out`` printed after it."""
        rest, _, date_line = output.rpartition(b"\n")
        body, _, status_line = rest.rpartition(b"\n")
        status = status_line.decode(errors="replace")
        if not status.isdigit() or not _MIN_STATUS <= int(status) <= _MAX_STATUS:
            raise _CurlUnusableError(f"unexpected output ending {output[-40:]!r}")
        date = date_line.decode(errors="replace").strip()
        if host == API_HOST:
            self._clock.observe_date(date)
        return Response(status=int(status), headers={"date": date} if date else {}, body=body)
