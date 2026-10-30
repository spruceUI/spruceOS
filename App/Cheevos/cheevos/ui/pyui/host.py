"""What a session asks of the PyUI process it runs in (.agents/pyui.md, "In-process sessions").

PyUI is already up when a session starts: Spruce's menus run the app inside PyUI's own process.
The session borrows its texture caches and gives them back empty, shows a message when it
fails, and changes Spruce's settings through PyUI, which keeps them in memory and would
otherwise write its own copy over a change made to the file.
"""

from __future__ import annotations

import logging

from cheevos.ui.pyui import texture_budget

logger = logging.getLogger(__name__)


def enter() -> None:
    """Put PyUI's texture caches on the app's budget for the session."""
    from devices.device import Device
    from display.display import Display

    device = Device.get_device()
    texture_budget.install(Display, device.screen_width(), device.screen_height())


def leave() -> None:
    """Free the session's textures and give PyUI back plain caches."""
    from display.display import Display

    texture_budget.uninstall(Display)


def show_message(text: str, seconds: float) -> None:
    """Show a message on a blank screen, the way Spruce shows its own.

    Args:
        text: The message; PyUI wraps it to the screen.
        seconds: How long it stays, blocking.
    """
    from display.display import Display

    Display.display_message(text, int(seconds * 1000))


def set_spruce_setting(section: str, name: str, value: str) -> None:
    """Change one of Spruce's text settings, when it has that setting and another value.

    PyUI saves Spruce's settings file and runs the setting's change command.

    Args:
        section: Settings section, e.g. ``"RetroAchievements Settings"``.
        name: Setting key, e.g. ``"webApiKey"``.
        value: The new value.
    """
    from utils.cfw_system_config import CfwSystemConfig

    current = CfwSystemConfig.get_selected_value(section, name)
    if isinstance(current, str) and current != value:
        CfwSystemConfig.set_menu_option(section, name, value)
        logger.info("Updated Spruce's %s setting", name)
