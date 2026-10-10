"""Device entry point: ``python -m cheevos``, started by ``App/Cheevos/launch.sh``.

``launch.sh`` prepares the platform's SDL environment and passes the PyUI device name in
``CHEEVOS_PYUI_DEVICE``; this module brings PyUI up and runs the app.
"""

from __future__ import annotations

import logging
import os
import signal
import sys
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path
from types import FrameType

STARTED_AT = time.monotonic()

from cheevos import app  # noqa: E402 — after STARTED_AT so start-up timing includes imports
from cheevos.platform.paths import Paths  # noqa: E402
from cheevos.ui.pyui import bootstrap  # noqa: E402

logger = logging.getLogger("cheevos")

_SDCARD = Path(os.environ.get("CHEEVOS_SDCARD_ROOT", "/mnt/SDCARD"))
_PYUI_DIR = _SDCARD / "App" / "PyUI"
_LOG_BYTES = 1024 * 1024


def _configure_logging(log_file: Path) -> logging.Logger:
    """Log to a rotating file (Spruce convention) and return the logger for PyUI.

    Args:
        log_file: Destination, e.g. ``Saves/spruce/cheevos-MiyooMini.log``.

    Returns:
        The logger PyUI's records are routed to (warnings and above).
    """
    log_file.parent.mkdir(parents=True, exist_ok=True)
    handler = RotatingFileHandler(log_file, maxBytes=_LOG_BYTES, backupCount=1, encoding="utf-8")
    formatter = logging.Formatter(
        "%(asctime)s.%(msecs)03dZ %(levelname)s %(name)s: %(message)s", "%Y-%m-%d %H:%M:%S"
    )
    # UTC: PyUI applies the saved time zone partway through start-up, so local times would jump.
    formatter.converter = time.gmtime
    handler.setFormatter(formatter)
    root = logging.getLogger()
    root.addHandler(handler)
    root.setLevel(logging.INFO)
    pyui_logger = logging.getLogger("cheevos.pyui")
    pyui_logger.setLevel(logging.WARNING)
    return pyui_logger


def _exit_on_sigterm(signum: int, _frame: FrameType | None) -> None:
    """Exit cleanly when Spruce (or a developer) sends SIGTERM.

    Args:
        signum: The received signal number.
    """
    logger.info("Received signal %d, exiting", signum)
    sys.exit(0)


def main() -> int:
    """Bring up PyUI on the device and run the app.

    Returns:
        Process exit code.
    """
    platform_name = os.environ.get("PLATFORM", "unknown")
    pyui_logger = _configure_logging(_SDCARD / "Saves" / "spruce" / f"cheevos-{platform_name}.log")
    device_name = os.environ.get("CHEEVOS_PYUI_DEVICE")
    if not device_name:
        logger.error("CHEEVOS_PYUI_DEVICE is not set; start the app through launch.sh")
        return 2
    signal.signal(signal.SIGTERM, _exit_on_sigterm)
    logger.info("Starting on %s (%s)", platform_name, device_name)

    bootstrap.add_pyui_to_path(_PYUI_DIR / "main-ui")
    bootstrap.install_logger(pyui_logger)
    setup = bootstrap.PyUiSetup(
        main_ui_dir=_PYUI_DIR / "main-ui",
        config_path=_PYUI_DIR / "py-ui-config.json",
        state_path=_SDCARD / "Saves" / "cheevos" / "pyui-state.json",
        cfw_config_path=_SDCARD / "Saves" / "spruce" / "spruce-config.json",
    )
    bootstrap.bootstrap(setup, lambda: bootstrap.hardware_device(device_name))
    logger.info("PyUI ready after %.2fs", time.monotonic() - STARTED_AT)

    try:
        env = app.AppEnvironment(paths=Paths.from_env())
        app.run(started_at=STARTED_AT, env=env)
    except Exception:
        logger.exception("Unhandled error")
        return 1
    logger.info("Exiting normally")
    return 0


if __name__ == "__main__":
    sys.exit(main())
