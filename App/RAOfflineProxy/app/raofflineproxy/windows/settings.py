from __future__ import annotations

"""Settings screen for the Windows menu, mirroring the Android app's Settings:
proxy port, autostart, Smart Cache on start, show locked achievements, update
checker, hide the Support button, usage stats, and clearing the cache or the
whole database. Mixed into WindowsMenuSession."""

import time

from .. import usage_stats
from . import history as windows_history
from ..config import MAX_PROXY_PORT, MIN_PROXY_PORT, load_config, proxy_port, save_config
from ..menu_sdl import ERROR_SECONDS
from ..platform import is_autostart_enabled
from ..rom_browser import clear_cached_games
from ..storage import (
    PENDING_AWARD_STATUS_DELETED,
    PENDING_AWARD_STATUS_FLUSHED,
    PENDING_AWARD_STATUS_PENDING,
    PENDING_AWARD_STATUS_STALE,
)

SETTINGS_VIEW = "win_settings"
CLEAR_CACHE_CONFIRM_VIEW = "win_clear_cache_confirm"
CLEAR_DATABASE_CONFIRM_VIEW = "win_clear_database_confirm"
STEAM_VIEW = "win_add_to_steam"
SETTINGS_LABEL = "Settings"

# config.json keys for the Windows-only settings.
SMART_CACHE_ON_START_KEY = "smart_cache_on_start"
SHOW_LOCKED_KEY = "show_locked_achievements"
UPDATE_CHECK_KEY = "update_check_enabled"
HIDE_SUPPORT_KEY = "hide_support_button"
# What B does on the main menu: "ask", "minimize" (close the menu window, the
# proxy and tray keep running) or "exit" (stop the proxy and tray too).
BACK_ACTION_KEY = "menu_back_action"
BACK_ACTIONS = ("ask", "minimize", "exit")
BACK_ACTION_NAMES = {"ask": "Ask", "minimize": "Minimize to tray", "exit": "Exit completely"}

# Defaults match the Android app.
SETTING_DEFAULTS = {
    SMART_CACHE_ON_START_KEY: True,
    SHOW_LOCKED_KEY: False,
    UPDATE_CHECK_KEY: True,
    HIDE_SUPPORT_KEY: False,
}

PORT_ROW = "Proxy port"
AUTOSTART_ROW = "Start with Windows"
REMOVE_CHECK_ROW = "Remove from Windows sign-in"
SMART_CACHE_ROW = "Smart Cache on proxy start"
SHOW_LOCKED_ROW = "Show locked achievements"
UPDATE_CHECK_ROW = "Check for updates"
HIDE_SUPPORT_ROW = "Hide \"Support me\""
BACK_ACTION_ROW = "B on the main menu"
USAGE_STATS_ROW = "Share anonymous usage stats"
STEAM_ROW = "Add to Steam"
CLEAR_CACHE_ROW = "Clear cache"
CLEAR_DATABASE_ROW = "Clear database"
BACK = "Back"

# A short description under the title for the row that is selected, as the
# Android app shows under each setting.
ROW_CAPTIONS = {
    PORT_ROW: "Local port the emulators use to reach the proxy. Stop the proxy to change it.",
    AUTOSTART_ROW: "Starts the proxy when you sign in to Windows. Off, sign-in starts it only if it was running when Windows went down, and otherwise puts the emulators back.",
    REMOVE_CHECK_ROW: "Removes RAOfflineProxy from Windows sign-in (the startup entry and sign-in task), for example before deleting this folder.",
    SMART_CACHE_ROW: "Prefetches achievement data for recently played games whenever the proxy starts.",
    SHOW_LOCKED_ROW: "Includes achievements you haven't unlocked yet in a game's achievement list.",
    UPDATE_CHECK_ROW: "Checks for new versions at startup and about once a day.",
    HIDE_SUPPORT_ROW: "Hides the Support me entry on the main menu.",
    BACK_ACTION_ROW: "Ask each time, minimize to the tray (the proxy keeps running), or exit completely (stops the proxy).",
    STEAM_ROW: "Adds RAOfflineProxy to your Steam library, to open it from Steam or Xbox mode.",
    USAGE_STATS_ROW: "Sends app version, device, OS and cache numbers once a day. Never your username.",
    CLEAR_CACHE_ROW: "Removes all cached games and cached RetroAchievements data.",
    CLEAR_DATABASE_ROW: "Removes all cached data, pending awards and award history.",
}


def windows_paths_root():
    from .paths import portable_root

    return portable_root()


def setting_enabled(config_data: dict, key: str) -> bool:
    return bool(config_data.get(key, SETTING_DEFAULTS[key]))


def back_action(config_data: dict) -> str:
    value = config_data.get(BACK_ACTION_KEY)
    return value if value in BACK_ACTIONS else "ask"


def on_off(value: bool) -> str:
    return "On" if value else "Off"


def start_tray() -> None:
    """The tray exits at once when one is already running (it holds a mutex)."""
    import subprocess

    from .process import pythonw_command

    try:
        subprocess.Popen(pythonw_command("raofflineproxy.windows.tray"))
    except OSError:
        pass


class SettingsMixin:
    def settings_rows(self) -> list[tuple[str, str | None]]:
        """(row name, value shown after it) in display order."""
        config_data = self.config_data
        from .autostart import check_removed

        return [
            (PORT_ROW, str(proxy_port(config_data))),
            (AUTOSTART_ROW, on_off(is_autostart_enabled(config_data))),
            # Gone once removed; turning Start with Windows on puts it back.
            *([] if check_removed(config_data) else [(REMOVE_CHECK_ROW, None)]),
            (SMART_CACHE_ROW, on_off(setting_enabled(config_data, SMART_CACHE_ON_START_KEY))),
            (SHOW_LOCKED_ROW, on_off(setting_enabled(config_data, SHOW_LOCKED_KEY))),
            (UPDATE_CHECK_ROW, on_off(setting_enabled(config_data, UPDATE_CHECK_KEY))),
            (HIDE_SUPPORT_ROW, on_off(setting_enabled(config_data, HIDE_SUPPORT_KEY))),
            (BACK_ACTION_ROW, BACK_ACTION_NAMES[back_action(config_data)]),
            (USAGE_STATS_ROW, on_off(usage_stats.load_consent(config_data) is True)),
            (STEAM_ROW, None),
            (CLEAR_CACHE_ROW, None),
            (CLEAR_DATABASE_ROW, None),
            (BACK, None),
        ]

    def settings_labels(self) -> list[str]:
        return [f"{name}: {value}" if value is not None else name for name, value in self.settings_rows()]

    def settings_status(self) -> str:
        rows = self.settings_rows()
        if 0 <= self.selected_index < len(rows):
            return ROW_CAPTIONS.get(rows[self.selected_index][0], "")
        return ""

    def open_settings(self) -> None:
        self.config_data = load_config()
        self.open_view(SETTINGS_VIEW, "main")

    def toggle_setting(self, key: str) -> None:
        self.config_data = load_config()
        self.config_data[key] = not setting_enabled(self.config_data, key)
        save_config(self.config_data)

    def activate_settings(self) -> None:
        rows = self.settings_rows()
        name = rows[self.selected_index][0]
        if name == BACK:
            self.return_to("main")
        elif name == PORT_ROW:
            self.edit_proxy_port()
        elif name == REMOVE_CHECK_ROW:
            self.remove_sign_in_check()
        elif name == AUTOSTART_ROW:
            self.config_data = load_config()
            self.change_autostart(not is_autostart_enabled(self.config_data))
        elif name == SMART_CACHE_ROW:
            self.toggle_setting(SMART_CACHE_ON_START_KEY)
        elif name == SHOW_LOCKED_ROW:
            self.toggle_setting(SHOW_LOCKED_KEY)
        elif name == UPDATE_CHECK_ROW:
            self.toggle_setting(UPDATE_CHECK_KEY)
        elif name == HIDE_SUPPORT_ROW:
            self.toggle_setting(HIDE_SUPPORT_KEY)
        elif name == BACK_ACTION_ROW:
            self.config_data = load_config()
            current = back_action(self.config_data)
            self.config_data[BACK_ACTION_KEY] = BACK_ACTIONS[(BACK_ACTIONS.index(current) + 1) % len(BACK_ACTIONS)]
            save_config(self.config_data)
        elif name == USAGE_STATS_ROW:
            self.set_usage_consent(usage_stats.load_consent(self.config_data) is not True)
            self.config_data = load_config()
        elif name == STEAM_ROW:
            self.open_add_to_steam()
        elif name == CLEAR_CACHE_ROW:
            self.open_view(CLEAR_CACHE_CONFIRM_VIEW)
            self.reset_selection()
        elif name == CLEAR_DATABASE_ROW:
            self.open_view(CLEAR_DATABASE_CONFIRM_VIEW)
            self.reset_selection()

    # Start with Windows ---------------------------------------------------------

    autostart_thread = None

    def change_autostart(self, enable: bool) -> None:
        """In the background: the admin prompt waits for an answer, and the menu
        keeps drawing (and stays responsive) meanwhile."""
        import threading

        if self.autostart_thread is not None and self.autostart_thread.is_alive():
            return

        def worker() -> None:
            try:
                if enable:
                    self.turn_on_autostart()
                else:
                    self.turn_off_autostart()
            except Exception as exc:  # e.g. the prompt left unanswered past the timeout
                self.flash(f"Start with Windows failed: {exc}", ERROR_SECONDS)
            # The setting lives in config.json, which the Settings rows read from here.
            self.config_data = load_config()

        if enable:
            self.flash("Waiting for the admin prompt...", 300)
        self.autostart_thread = threading.Thread(target=worker, daemon=True)
        self.autostart_thread.start()

    def turn_on_autostart(self) -> None:
        """A logon task needs one admin prompt; without it, the Run entry, which
        Windows' Xbox full screen mode doesn't start."""
        from . import autostart as windows_autostart

        if windows_autostart.enable() == "task":
            self.flash("Starts when you sign in, in Xbox mode too", 3)
        else:
            self.flash("Starts when you sign in (not in Xbox mode: the admin prompt was declined)", 5)

    def turn_off_autostart(self) -> None:
        from . import autostart as windows_autostart

        windows_autostart.disable()
        self.flash("Start with Windows is off", 3)

    def remove_sign_in_check(self) -> None:
        """In the background, like the other admin prompt, and never alongside
        it (one admin prompt at a time)."""
        import threading

        from . import autostart as windows_autostart

        if self.autostart_thread is not None and self.autostart_thread.is_alive():
            return

        def worker() -> None:
            if windows_autostart.remove_sign_in_check():
                self.flash("Removed from Windows sign-in", 3)
            else:
                self.flash("Not removed: the admin prompt was declined", ERROR_SECONDS)
            self.config_data = load_config()

        self.flash("Removing from Windows sign-in...", 300)
        self.autostart_thread = threading.Thread(target=worker, daemon=True)
        self.autostart_thread.start()

    # Add to Steam ---------------------------------------------------------------

    steam_accounts: list = []
    steam_thread = None
    steam_was_running = False

    def open_add_to_steam(self) -> None:
        from . import steam as windows_steam

        if windows_paths_root() is None:
            self.flash("Add to Steam needs the portable RAOfflineProxy folder", ERROR_SECONDS)
            return
        self.steam_accounts = windows_steam.accounts()
        if not self.steam_accounts:
            self.flash("Steam isn't installed, or no one has signed in to it yet", ERROR_SECONDS)
            return
        self.steam_was_running = windows_steam.steam_running()
        self.open_view(STEAM_VIEW)
        self.reset_selection()

    def steam_labels(self) -> list[str]:
        if len(self.steam_accounts) == 1:
            return ["Add to Steam", "Cancel"]
        return [f"Add to {account.name}" for account in self.steam_accounts] + ["Cancel"]

    def steam_status(self) -> str:
        if self.steam_thread is not None and self.steam_thread.is_alive():
            return "Adding to Steam..."
        text = "Adds RAOfflineProxy to your Steam library with its artwork, so you can open it from Steam or Xbox mode."
        if len(self.steam_accounts) == 1:
            text += f" Steam account: {self.steam_accounts[0].name}."
        if self.steam_was_running:
            text += " Steam closes and reopens to pick it up."
        return text

    def activate_steam(self) -> None:
        import threading

        index = self.selected_index
        if index >= len(self.steam_accounts):  # Cancel
            self.return_to(SETTINGS_VIEW)
            return
        if self.steam_thread is not None and self.steam_thread.is_alive():
            return
        account = self.steam_accounts[index]

        def worker() -> None:
            from pathlib import Path

            from . import steam as windows_steam
            from .tray import write_icon

            root = windows_steam.steam_root()
            closed = False
            try:
                if windows_steam.steam_running():
                    if not windows_steam.close_steam(root):
                        self.flash("Steam didn't close. Close it and try again.", ERROR_SECONDS)
                        return
                    closed = True
                logo = Path(__file__).resolve().parent.parent / "logo-320.png"
                windows_steam.add_to_steam(account, windows_paths_root(), write_icon(), logo)
                self.flash("Added to Steam", 3)
            except (OSError, ValueError) as exc:
                self.flash(f"Add to Steam failed: {exc}", ERROR_SECONDS)
            finally:
                # Reopened even after a failure: it was closed for this.
                if closed:
                    windows_steam.start_steam(root)

        # Before the thread starts, so it can't replace the thread's result.
        self.return_to(SETTINGS_VIEW)
        self.flash("Adding to Steam...", 60)
        self.steam_thread = threading.Thread(target=worker, daemon=True)
        self.steam_thread.start()

    # Proxy port ---------------------------------------------------------------

    def edit_proxy_port(self) -> None:
        if self.proxy_running():
            self.flash("Stop the proxy to change the port", ERROR_SECONDS)
            return
        self.open_keyboard(
            "Proxy Port",
            f"Port between {MIN_PROXY_PORT} and {MAX_PROXY_PORT}.",
            self.save_proxy_port,
            initial=str(proxy_port(self.config_data)),
            numeric=True,
            max_length=5,
        )

    def save_proxy_port(self, text: str) -> None:
        try:
            port = int(text)
        except ValueError:
            port = 0
        if not (MIN_PROXY_PORT <= port <= MAX_PROXY_PORT):
            self.flash(f"Enter a port between {MIN_PROXY_PORT} and {MAX_PROXY_PORT}.", ERROR_SECONDS)
            return
        self.config_data = load_config()
        self.config_data["proxy_port"] = port
        save_config(self.config_data)
        self.flash(f"Proxy port set to {port}")

    # Clearing ---------------------------------------------------------------

    def activate_clear_cache_confirm(self) -> None:
        if self.selected_label() == "YES":
            clear_cached_games(self.storage)
            self.refresh_cached_games()
            self.flash("Cache cleared")
        self.return_to(SETTINGS_VIEW)

    def activate_clear_database_confirm(self) -> None:
        if self.selected_label() == "YES":
            clear_cached_games(self.storage)
            self.storage.delete_pending_awards_by_statuses(
                [
                    PENDING_AWARD_STATUS_PENDING,
                    PENDING_AWARD_STATUS_FLUSHED,
                    PENDING_AWARD_STATUS_DELETED,
                    PENDING_AWARD_STATUS_STALE,
                ]
            )
            windows_history.clear_history()
            self.refresh_cached_games()
            self.flash("Database cleared")
        self.return_to(SETTINGS_VIEW)

    def clear_database_warning(self) -> str:
        pending = len(self.pending_awards)
        text = "This removes all cached games, pending awards and award history."
        if pending:
            text += f" {pending} pending award(s) have not synced yet and will be lost."
        return text

    # Smart Cache on proxy start ------------------------------------------------

    def start_proxy(self) -> None:
        super().start_proxy()
        start_tray()
        if not setting_enabled(load_config(), SMART_CACHE_ON_START_KEY):
            return
        if not (self.main_online and self.main_logged_in) or self.smart_cache_in_progress:
            return
        # The Android setting runs it without asking, so skip the shared prompt.
        if self.view == "smart_cache_prompt":
            self.view = "main"
            self.restore_view_position("main")
        self.start_smart_cache()
        self.message = ("Proxy started, Smart Cache running", time.monotonic() + 1.5)
