"""Run a sync from the command line: ``python -m cheevos.core.sync [--full] [--scope ...]``.

Development tool: exercises the real API, caches and badge downloads without the UI. On a
device run it with ``SSL_CERT_FILE`` set (Spruce's CA bundle); on the desktop it uses the dev
SD card when ``CHEEVOS_SDCARD_ROOT`` points at it.
"""

from __future__ import annotations

import argparse
import logging
import sys
import threading
import time

from cheevos.core.errors import ConfigError
from cheevos.core.net import is_online
from cheevos.core.settings import BadgeScope, load_settings
from cheevos.core.sync.engine import SyncEngine, SyncOptions
from cheevos.core.sync.progress import ProgressTracker
from cheevos.core.sync.session import load_credentials, open_sync_deps
from cheevos.platform.paths import Paths

logger = logging.getLogger("cheevos.sync.cli")


def _report(tracker: ProgressTracker, done: threading.Event) -> None:
    """Log progress every second until ``done`` is set.

    Args:
        tracker: Progress source.
        done: Stop signal.
    """
    last = None
    while not done.wait(1.0):
        status = tracker.snapshot()
        line = (status.phase.value, status.done, status.total, status.current)
        if line != last:
            eta = f" eta {status.eta_seconds:.0f}s" if status.eta_seconds else ""
            logger.info(
                "%s %d/%d %s%s", status.phase.value, status.done, status.total, status.current, eta
            )
            last = line


def main(argv: list[str] | None = None) -> int:
    """Run one sync in the foreground.

    Args:
        argv: Arguments without the program name; ``None`` reads ``sys.argv``.

    Returns:
        ``0`` when the sync finished, ``1`` otherwise.
    """
    parser = argparse.ArgumentParser(prog="python -m cheevos.core.sync")
    parser.add_argument("--full", action="store_true", help="download every game's details")
    parser.add_argument("--scope", choices=[scope.value for scope in BadgeScope], default=None)
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s: %(message)s")

    paths = Paths.from_env()
    settings = load_settings(paths.settings_file)
    try:
        credentials = load_credentials(paths)
    except ConfigError as exc:
        logger.error("%s", exc)  # noqa: TRY400 — expected configuration problem, no traceback
        return 1
    options = SyncOptions(
        full=args.full,
        badge_scope=BadgeScope(args.scope) if args.scope else settings.badge_scope,
        recent_days=settings.recent_days,
    )
    deps = open_sync_deps(paths, credentials)
    tracker = ProgressTracker()
    done = threading.Event()
    reporter = threading.Thread(target=_report, args=(tracker, done), daemon=True)
    reporter.start()
    started = time.monotonic()
    try:
        engine = SyncEngine(deps, tracker, threading.Event(), online=is_online)
        status = engine.run(options)
    finally:
        done.set()
        deps.close()
    logger.info(
        "Finished %s in %.1fs: %d details, %d images%s",
        status.phase.value,
        time.monotonic() - started,
        status.details_fetched,
        status.media_fetched,
        f" ({status.failure.value})" if status.failure else "",
    )
    return 0 if status.failure is None and status.phase.value == "done" else 1


if __name__ == "__main__":
    sys.exit(main())
