"""Spruce's ROM identification helper: ``python -m cheevos.platform.identify_rom``.

``App/Cheevos/identify-rom.sh`` starts it for the game menu's "View achievement progress"
(.agents/integration.md)::

    identify-rom.sh --path "$ROM" --work-dir "$SCRATCH" --json

It prints one JSON object on stdout (``cheevos.core.identification.result``) and exits 0 for a
match or a confirmed miss, 1 for an error; Spruce reads the JSON whatever the exit status.
Diagnostics go to the app log. It is headless: no PyUI, SDL, screens, sync or account data, and
nothing from RAOfflineProxy but its hashing wrapper, imported only when a path must be hashed.
SIGTERM (Spruce's cancel) unwinds, so a ZIP's extraction directory is removed.
"""

from __future__ import annotations

import argparse
import json
import logging
import signal
import sys
import time
from pathlib import Path
from types import FrameType
from typing import TYPE_CHECKING

from cheevos.core.clock import network_clock
from cheevos.core.identification.identify import Sources, identify_rom
from cheevos.core.identification.path_cache import PathCache
from cheevos.core.identification.result import ERROR, UNAVAILABLE, Identification
from cheevos.platform.paths import Paths

if TYPE_CHECKING:
    from cheevos.core.identification.candidates import Hasher
    from cheevos.core.identification.hash_lookup import HashResolver

logger = logging.getLogger("cheevos.identify")

HTTP_TIMEOUT = 15.0


def _absolute_path(value: str) -> str:
    """Accept an absolute ROM path: the launcher runs from the app's own directory."""
    if not Path(value).is_absolute():
        raise argparse.ArgumentTypeError("expected an absolute path")
    return value


def _parse(argv: list[str] | None) -> argparse.Namespace:
    """Read the command line."""
    parser = argparse.ArgumentParser(
        prog="identify-rom.sh", description="Identify a ROM's RetroAchievements game."
    )
    parser.add_argument(
        "--path", required=True, type=_absolute_path, help="the ROM file's absolute path"
    )
    parser.add_argument(
        "--work-dir",
        type=Path,
        help="SD-card directory for extracting a zipped ROM "
        "(default: Saves/cheevos/cache/identify-work)",
    )
    parser.add_argument("--json", action="store_true", help="print the result as JSON")
    return parser.parse_args(argv)


def _configure_logging(log_file: Path) -> None:
    """Append to the app log, in the app's UTC format; stderr if the log can't be opened."""
    handler: logging.Handler
    try:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        # A plain FileHandler: the app's RotatingFileHandler rotates the file when it next runs.
        handler = logging.FileHandler(log_file, encoding="utf-8")
    except OSError:
        handler = logging.StreamHandler(sys.stderr)
    formatter = logging.Formatter(
        "%(asctime)s.%(msecs)03dZ %(levelname)s %(name)s: %(message)s", "%Y-%m-%d %H:%M:%S"
    )
    formatter.converter = time.gmtime
    handler.setFormatter(formatter)
    root = logging.getLogger()
    root.addHandler(handler)
    root.setLevel(logging.INFO)


def _exit_on_signal(signum: int, _frame: FrameType | None) -> None:
    """Unwind on SIGTERM, so ``finally`` blocks remove the extraction directory."""
    raise SystemExit(128 + signum)


def build_sources(paths: Paths, work_dir: Path) -> Sources:
    """Wire the installed proxy and RA, each loaded only when a path must be hashed.

    Args:
        paths: Device paths.
        work_dir: SD-card directory for extracting a zipped ROM.

    Returns:
        The collaborators.
    """

    def load_hasher() -> Hasher:
        """Import the proxy's hashing wrapper (the adapter imports it lazily)."""
        from cheevos.platform.proxy_hasher import load_proxy_hasher

        return load_proxy_hasher(paths.proxy_app_dir)

    def ra_lookup() -> HashResolver:
        """Create RA's hash lookup over the app's HTTPS transport."""
        from cheevos.core.identification.hash_lookup import RaHashLookup
        from cheevos.core.ra_client.transport import HttpTransport, default_user_agent

        transport = HttpTransport(timeout=HTTP_TIMEOUT)
        return RaHashLookup(transport, default_user_agent(paths.platform))

    return Sources(
        load_hasher=load_hasher,
        work_dir=work_dir,
        proxy_database=paths.proxy_data_dir / "proxy.sqlite3",
        ra_lookup=ra_lookup,
        now=network_clock.now,
    )


def run(path: str, *, paths: Paths, sources: Sources) -> Identification:
    """Identify one ROM; an unexpected failure is the ``unavailable`` error.

    Args:
        path: The ROM path from Spruce.
        paths: Device paths.
        sources: Hashing and lookup collaborators.

    Returns:
        The outcome.
    """
    cache = PathCache(paths.rom_identifications_file, now=network_clock.now)
    try:
        return identify_rom(path, cache=cache, sources=sources)
    except Exception:  # Spruce must always get a structured answer
        logger.exception("Identification failed unexpectedly")
        return Identification.error(UNAVAILABLE)


def _format(result: Identification, *, as_json: bool) -> str:
    """Render the result for stdout."""
    if as_json:
        return json.dumps(result.to_json(), separators=(",", ":"))
    if result.game_id is not None:
        return f"matched: game {result.game_id}"
    return f"error: {result.reason}" if result.status == ERROR else "no match"


def main(argv: list[str] | None = None) -> int:
    """Identify the ROM given on the command line.

    Args:
        argv: Arguments without the program name; ``sys.argv`` when ``None``.

    Returns:
        0 for a match or a confirmed miss, 1 for an error.
    """
    args = _parse(argv)
    paths = Paths.from_env()
    _configure_logging(paths.log_file)
    signal.signal(signal.SIGTERM, _exit_on_signal)
    sources = build_sources(paths, args.work_dir or paths.identify_work_dir)
    started = time.monotonic()
    result = run(args.path, paths=paths, sources=sources)
    logger.info("Identification took %.2fs", time.monotonic() - started)
    sys.stdout.write(_format(result, as_json=args.json) + "\n")
    sys.stdout.flush()
    return 1 if result.status == ERROR else 0


if __name__ == "__main__":
    sys.exit(main())
