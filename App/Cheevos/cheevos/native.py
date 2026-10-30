"""Cheevos's entry point: it runs inside PyUI's own process, the way Spruce's menus open it.

PyUI calls :func:`run` (``"pyuiEntry"`` in ``config.json``) from its Apps menu or its game
menu, with its display, theme and controller already up, and carries on when it returns. A
:func:`session` puts the app's hooks into PyUI, runs it, then takes every hook out again and
waits for the app's workers, so that nothing of Cheevos keeps running or stays referenced and
PyUI can drop its modules (.agents/pyui.md, "In-process sessions"). The desktop runner brings
PyUI up itself, then runs the same session with recorded fixtures.
"""

from __future__ import annotations

import contextlib
import logging
import threading
import time
from collections.abc import Iterator
from logging.handlers import RotatingFileHandler
from pathlib import Path

from cheevos import app
from cheevos.core.credentials import RA_SETTINGS_SECTION, read_api_key
from cheevos.core.ra_client.redact import uninstall_redaction
from cheevos.platform.paths import Paths
from cheevos.ui import strings
from cheevos.ui.pyui import host

logger = logging.getLogger(__name__)

APP_LOGGER = "cheevos"  # every module logs under it (``logging.getLogger(__name__)``)
WORKER_PREFIX = "cheevos-"  # the app's worker threads: cheevos-sync, cheevos-details, ...
_LOG_BYTES = 1024 * 1024
_WORKERS_TIMEOUT = 2.0  # on top of the app's own waits for each worker
_ERROR_SECONDS = 5.0


def run(game_id: int | None = None) -> None:
    """Run one session for PyUI, logged to the app's own log. Never raises.

    An error is logged and shown, and PyUI's menu carries on after the message.

    Args:
        game_id: Open this game only, for Spruce's "View achievement progress"; B returns to
            Spruce's game menu.
    """
    started_at = time.monotonic()
    paths = Paths.from_env()
    with app_log(paths.log_file):
        logger.info("Opening in PyUI on %s", paths.platform)
        try:
            session(app.AppEnvironment(paths=paths), started_at=started_at, game_id=game_id)
        except Exception:
            logger.exception("Unhandled error")
            log_path = paths.log_file.relative_to(paths.sdcard)
            host.show_message(strings.APP_FAILED.format(log=log_path), _ERROR_SECONDS)
        logger.info("Closed after %.1fs", time.monotonic() - started_at)


def session(env: app.AppEnvironment, *, started_at: float, game_id: int | None = None) -> None:
    """Run the app once in an initialised PyUI, then take all of it out of PyUI again.

    Args:
        env: App environment.
        started_at: ``time.monotonic()`` when the app was asked to open.
        game_id: Open this game only (see :func:`run`).
    """
    with contextlib.ExitStack() as cleanup:  # undone in reverse, each step even if one fails
        cleanup.callback(uninstall_redaction)  # last: the workers may still log the key
        cleanup.callback(_await_workers)
        host.enter()
        cleanup.callback(host.leave)
        cleanup.callback(_share_api_key, env.paths)
        app.run(started_at=started_at, env=env, game_id=game_id)


@contextlib.contextmanager
def app_log(log_file: Path) -> Iterator[None]:
    """Log the app to its own file during the block (Spruce's ``Saves/spruce/<app>-*.log``).

    The handler sits on the app's top logger, which stops propagating, so the app's records
    stay out of PyUI's log, and PyUI's own records stay out of the app's.

    Args:
        log_file: Destination, e.g. ``Saves/spruce/cheevos-MiyooMini.log``.

    Yields:
        Nothing.
    """
    log_file.parent.mkdir(parents=True, exist_ok=True)
    handler = RotatingFileHandler(log_file, maxBytes=_LOG_BYTES, backupCount=1, encoding="utf-8")
    formatter = logging.Formatter(
        "%(asctime)s.%(msecs)03dZ %(levelname)s %(name)s: %(message)s", "%Y-%m-%d %H:%M:%S"
    )
    # UTC, marked Z: comparable across time-zone changes and with the app's earlier logs.
    formatter.converter = time.gmtime
    handler.setFormatter(formatter)
    top = logging.getLogger(APP_LOGGER)
    level, propagate = top.level, top.propagate
    top.addHandler(handler)
    top.setLevel(logging.INFO)
    top.propagate = False
    try:
        yield
    finally:
        top.removeHandler(handler)
        handler.close()
        top.setLevel(level)
        top.propagate = propagate


def _share_api_key(paths: Paths) -> None:
    """Copy the key into Spruce's Web API Key setting, so a key typed in the app shows there.

    Args:
        paths: Device paths.
    """
    host.set_spruce_setting(RA_SETTINGS_SECTION, "webApiKey", read_api_key(paths) or "")


def _await_workers(timeout: float = _WORKERS_TIMEOUT) -> None:
    """Wait for the app's workers to finish: they close their sockets and caches as they end.

    Args:
        timeout: Seconds to wait in all.
    """
    deadline = time.monotonic() + timeout
    for thread in threading.enumerate():
        if thread.name.startswith(WORKER_PREFIX):
            thread.join(max(0.0, deadline - time.monotonic()))
    if left := [t.name for t in threading.enumerate() if t.name.startswith(WORKER_PREFIX)]:
        logger.warning("Workers still running at exit: %s", ", ".join(left))
