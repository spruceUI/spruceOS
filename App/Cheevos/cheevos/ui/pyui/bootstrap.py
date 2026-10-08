"""Start PyUI's subsystems from outside PyUI.

Mirrors the start-up order of PyUI's ``mainui.py`` (config, device, state, theme, display,
controller) without the parts that belong to the launcher itself: menu loops, background
threads, theme conversion and the stdout/stderr redirection done by ``PyUiLogger.init``.
"""

from __future__ import annotations

import logging
import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from cheevos.ui.pyui import texture_budget

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class PyUiSetup:
    """Everything needed to bring PyUI up.

    Attributes:
        main_ui_dir: PyUI's ``main-ui`` directory (contains ``mainui.py``).
        config_path: PyUI config JSON; its ``themeDir`` key locates the themes directory.
        state_path: Where PyUI keeps its view state (last selections). Kept separate from
            PyUI's own state file so the app never alters the launcher's.
        theme: Theme folder name inside ``themeDir``, e.g. ``"SPRUCE"``. ``None`` uses the
            theme the user selected in Spruce (the device's system config).
        cfw_config_path: Spruce's ``spruce-config.json``, or ``None`` when there is none
            (desktop).
        user_config_path: Override for PyUI's ``pyui-common.json`` location, which PyUI
            hard-codes to the SD card. ``None`` keeps PyUI's default (correct on a device).
    """

    main_ui_dir: Path
    config_path: Path
    state_path: Path
    theme: str | None = None
    cfw_config_path: Path | None = None
    user_config_path: Path | None = None


def add_pyui_to_path(main_ui_dir: Path) -> None:
    """Make PyUI's top-level packages importable.

    PyUI must sit at ``sys.path[0]``: its ``Language`` class finds the ``lang`` directory
    relative to ``sys.path[0]``.

    Args:
        main_ui_dir: PyUI's ``main-ui`` directory.

    Raises:
        FileNotFoundError: If ``main_ui_dir`` does not contain ``mainui.py``.
    """
    if not (main_ui_dir / "mainui.py").is_file():
        raise FileNotFoundError(f"PyUI not found at {main_ui_dir}")
    entry = str(main_ui_dir)
    if entry in sys.path:
        sys.path.remove(entry)
    sys.path.insert(0, entry)


def install_logger(pyui_logger: logging.Logger) -> None:
    """Route PyUI's logging into ``pyui_logger`` instead of calling ``PyUiLogger.init``.

    ``PyUiLogger.init`` replaces ``sys.stdout``/``sys.stderr`` and adds its own handlers;
    every PyUI module only ever calls ``PyUiLogger.get_logger()``, so injecting the cached
    logger is enough.

    Args:
        pyui_logger: Logger that receives all PyUI log records.
    """
    from utils.logger import PyUiLogger

    # Private attribute, but it is PyUI's only logger handle; see the docstring.
    PyUiLogger._logger = pyui_logger


def bootstrap(setup: PyUiSetup, device_factory: Callable[[], object]) -> None:
    """Initialise PyUI's config, device, theme, display and controller.

    Call :func:`add_pyui_to_path` and :func:`install_logger` first.

    Args:
        setup: Paths and theme to use.
        device_factory: Creates the PyUI device object (a real device class on hardware, the
            desktop shim during development). Called after configs are loaded, because device
            constructors read them.
    """
    from controller.controller import Controller
    from devices.device import Device
    from devices.miyoo.user_config import UserConfig
    from display.display import Display
    from menus.language.language import Language
    from themes.theme import Theme
    from utils.cfw_system_config import CfwSystemConfig
    from utils.py_ui_config import PyUiConfig
    from utils.py_ui_state import PyUiState

    PyUiConfig.init(str(setup.config_path))
    if setup.user_config_path is not None:
        UserConfig.FILEPATH = str(setup.user_config_path)
    UserConfig.reload_config()
    CfwSystemConfig.init(str(setup.cfw_config_path) if setup.cfw_config_path else None)
    Language.init()

    Device.init(device_factory())
    device = Device.get_device()
    # TZ lives only in the process environment; PyUI's launcher re-applies the saved zone at
    # every start, and so must we, or clocks show UTC.
    device.restore_saved_timezone()
    setup.state_path.parent.mkdir(parents=True, exist_ok=True)
    if not setup.state_path.exists():
        setup.state_path.write_text("{}", encoding="utf-8")
    PyUiState.init(str(setup.state_path))

    theme = setup.theme or device.get_system_config().get_theme()
    theme_dir = Path(PyUiConfig.get("themeDir")) / theme
    logger.info("PyUI theme %s at %dx%d", theme_dir, device.screen_width(), device.screen_height())
    Theme.init(str(theme_dir), device.screen_width(), device.screen_height())
    Display.init()
    texture_budget.install(Display, device.screen_width(), device.screen_height())
    Display.present()
    Controller.init()


def hardware_device(name: str) -> object:
    """Create PyUI's device object for real hardware, exactly as PyUI's launcher does.

    Reuses ``mainui.initialize_device`` so every device Spruce supports works without a copy
    of its device table. Importing ``mainui`` does not start PyUI (its ``main()`` is guarded).

    Args:
        name: PyUI device name as passed to ``mainui.py -device``, e.g. ``"MIYOO_MINI_PLUS"``.

    Returns:
        The initialised device, also registered with PyUI's ``Device`` holder.
    """
    from devices.device import Device
    from mainui import initialize_device

    # main_ui_mode=False: none of the launcher-only background services.
    initialize_device(name, main_ui_mode=False)
    device = Device.get_device()
    _enable_backlight_control(device)
    return device


def _enable_backlight_control(device: object) -> None:
    """Give Miyoo Mini devices the backlight helper PyUI only creates in launcher mode.

    PyUI's screensaver dims and restores the backlight through
    ``miyoo_mini_flip_shared_memory_writer``; outside launcher mode that attribute is missing,
    so the screensaver failed to dim ("object has no attribute ...") and the screen stayed at
    full brightness while idle in Cheevos.

    Args:
        device: The PyUI device object.
    """
    if hasattr(device, "miyoo_mini_flip_shared_memory_writer"):
        return
    if not hasattr(type(device), "_set_lumination_to_config"):
        return  # not a Miyoo Mini family device
    from devices.miyoo.mini.miyoo_mini_flip_shared_memory_writer import (
        MiyooMiniFlipSharedMemoryWriter,
    )

    writer = MiyooMiniFlipSharedMemoryWriter()
    setattr(device, "miyoo_mini_flip_shared_memory_writer", writer)  # noqa: B010 — PyUI device attr
