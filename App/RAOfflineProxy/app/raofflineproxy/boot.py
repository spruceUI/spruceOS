"""Boot entrypoint that opens the proxy port before anything else runs.

Importing the full package and starting the service process costs several
seconds on handheld hardware. muOS launches the last played content in parallel
with its user-init scripts, so the emulator can reach its RetroAchievements
login before the service is up — and a refused connection makes rcheevos
disable achievements for the whole session.

Binding here, with only the stdlib loaded, means the port is listening within a
fraction of that time. Connections that arrive before the service is ready sit
in the accept queue instead of being refused. The listening socket is handed to
the service process through LISTEN_FD_ENV.
"""

from __future__ import annotations

import os
import socket
import sys

LISTEN_FD_ENV = "RAOFFLINEPROXY_LISTEN_FD"
LISTEN_BACKLOG = 32
PREBIND_COMMANDS = ("boot-reconcile", "start-proxy")


def prebind_listen_socket() -> socket.socket | None:
    from .config import load_config, proxy_host, proxy_port

    config_data = load_config()
    address = (proxy_host(config_data), proxy_port(config_data))

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(address)
        sock.listen(LISTEN_BACKLOG)
    except OSError:
        # Most likely a service is already running and holding the port.
        sock.close()
        return None

    sock.set_inheritable(True)
    return sock


def adopt_listen_socket() -> socket.socket | None:
    """Reclaim the socket handed over by the boot entrypoint, if any."""
    raw_fd = os.environ.pop(LISTEN_FD_ENV, None)
    if not raw_fd:
        return None

    try:
        fd = int(raw_fd)
    except ValueError:
        return None

    try:
        return socket.socket(socket.AF_INET, socket.SOCK_STREAM, fileno=fd)
    except OSError:
        return None


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    listen_socket = prebind_listen_socket() if command in PREBIND_COMMANDS else None
    if listen_socket is not None:
        os.environ[LISTEN_FD_ENV] = str(listen_socket.fileno())

    from .main import main as run_main

    try:
        run_main()
    finally:
        if listen_socket is not None:
            listen_socket.close()


if __name__ == "__main__":
    sys.exit(main())
