from __future__ import annotations

"""The SDL menu on Windows: the shared MenuSdlSession plus the Android app's
features the Linux menu doesn't have. Every Windows-only screen is a view
handled here; anything else falls through to the shared menu, so the Linux
devices never run this code. A feature the Linux side wants can move up into
menu_sdl.py as is."""

import os
import stat
import string
import time
from pathlib import Path

from .. import watch_folders
from . import history as windows_history
from ..config import load_config, save_config
from ..menu_sdl import ERROR_SECONDS, GROUP_GAP, MenuSdlSession
from .input import read_keys
from ..pending_awards import PendingAwardEntry
from ..rom_browser import EXCLUDED_BROWSER_DIR_NAMES, is_supported_browser_file
from .account import (
    LOGIN_LABEL,
    LOGIN_PROGRESS_VIEW,
    SEND_LOGS_DETAILS_VIEW,
    SEND_LOGS_ONLY,
    SEND_LOGS_WITH_DETAILS,
    AccountMixin,
)
from . import background as windows_background
from . import emulators as windows_emulators
from .support import (
    HELP_LABEL,
    HELP_VIEW,
    SUPPORT_AMOUNTS_VIEW,
    SUPPORT_DELIVERY_VIEW,
    SUPPORT_VIEW,
    UPDATE_VIEW,
    SupportMixin,
)
from .support import EMAIL_LINK as SUPPORT_EMAIL_LINK
from .support import OPEN_IN_BROWSER as SUPPORT_OPEN_IN_BROWSER
from .emulators_menu import EMULATOR_ACTIONS_VIEW, EMULATORS_LABEL, EMULATORS_VIEW, EmulatorsMixin
from .games import CONSOLE_ACTIONS_VIEW, CONSOLE_REMOVE_CONFIRM_VIEW, GamesMixin
from .keyboard import KEYBOARD_VIEW, KeyboardMixin
from .mouse import MouseMixin
from .status import StatusPanelMixin
from .settings import (
    CLEAR_CACHE_CONFIRM_VIEW,
    CLEAR_DATABASE_CONFIRM_VIEW,
    HIDE_SUPPORT_KEY,
    SETTINGS_LABEL,
    SETTINGS_VIEW,
    STEAM_VIEW,
    SettingsMixin,
    back_action,
    setting_enabled,
)
from ..storage import PENDING_AWARD_STATUS_PENDING

LAST_BROWSER_DIR_KEY = "rom_browser_last_dir"
MESSAGE_SECONDS = 1.5
EXIT_CONFIRM_VIEW = "win_exit_confirm"
AUTOSTART_ASK_VIEW = "win_autostart_ask"
AUTOSTART_ASKED_KEY = "autostart_asked"
MINIMIZE_TO_TRAY = "Minimize to tray"
EXIT_COMPLETELY = "Exit completely"

# Main-menu entries added on Windows, inserted ahead of "Support me".
WATCHED_FOLDERS_LABEL = "Watched folders"
AWARDS_HISTORY_LABEL = "Awards history"

# File browser rows that aren't folder entries.
ADD_FOLDER = "Add folder"
WATCH_FOLDER = "Watch this folder"
UNWATCH_FOLDER = "Stop watching this folder"
PARENT = ".."
CANCEL = "Cancel"
BACK = "Back"
CLEAR_HISTORY = "Clear award history"
MOVED_TO_SETTINGS = {
    "Enable autostart",
    "Disable autostart",
    "Enable usage stats",
    "Disable usage stats",
}


def list_drives() -> list[Path]:
    return [Path(f"{letter}:\\") for letter in string.ascii_uppercase if Path(f"{letter}:\\").exists()]


def list_folder(path: Path, wanted_files=None) -> list[Path]:
    """rom_browser.list_browser_entries_fast with the same exclusions and ROM
    filter, but tolerant of what Windows won't let it read: it skips hidden and
    system folders (System Volume Information, $RECYCLE.BIN) and any entry that
    errors, where the shared listing fails as a whole. Also used to pick an
    emulator's exe, via wanted_files."""
    hidden = stat.FILE_ATTRIBUTE_HIDDEN | stat.FILE_ATTRIBUTE_SYSTEM
    folders: list[Path] = []
    files: list[Path] = []
    with os.scandir(path) as entries:
        for entry in entries:
            if entry.name.startswith((".", "$")):
                continue
            try:
                if entry.stat().st_file_attributes & hidden:
                    continue
                if entry.is_dir():
                    if entry.name not in EXCLUDED_BROWSER_DIR_NAMES:
                        folders.append(Path(entry.path))
                elif (wanted_files(entry.name) if wanted_files else is_supported_browser_file(Path(entry.path))):
                    files.append(Path(entry.path))
            except OSError:
                continue
    return sorted(folders, key=lambda p: p.name.lower()) + sorted(files, key=lambda p: p.name.lower())


class WindowsMenuSession(MouseMixin, StatusPanelMixin, SupportMixin, EmulatorsMixin, AccountMixin, GamesMixin, SettingsMixin, KeyboardMixin, MenuSdlSession):
    def __init__(self, *args, **kwargs) -> None:
        # The file browser starts on the drive list when browser_dir is None
        # and this is true; the shared code reads browser_dir None as "no ROM
        # directory", so the flag keeps the two apart.
        self.at_drive_list = False
        self.drives: list[Path] = []
        self.awards_history: list[PendingAwardEntry] = []
        self.active_watched_folder: str | None = None
        # Set while the browser is picking an emulator's exe instead of ROMs.
        self.browser_pick_kind = None
        self.active_emulator = None
        self.emulator_detect_thread = None
        super().__init__(*args, **kwargs)
        self.start_update_check()

    def app_version_text(self) -> str:
        from ..config import APP_VERSION

        return APP_VERSION

    def maybe_show_usage_consent(self) -> None:
        """Test builds skip the usage question (they never report, see
        usage_report). Then, once, the Start with Windows question."""
        from .paths import test_channel

        if not test_channel():
            super().maybe_show_usage_consent()
        if self.view == "main":
            self.maybe_ask_autostart()

    def maybe_ask_autostart(self) -> None:
        """Asked once on the first start rather than defaulted: the proxy only
        helps when it's running, but turning it on writes to the PC, which a
        portable folder shouldn't do unasked."""
        from .paths import portable_root

        if portable_root() is None or self.config_data.get(AUTOSTART_ASKED_KEY):
            return
        self.save_view_position("main")
        self.view = AUTOSTART_ASK_VIEW
        self.reset_selection()

    def answer_autostart(self, enable: bool) -> None:
        self.config_data = load_config()
        self.config_data[AUTOSTART_ASKED_KEY] = True
        save_config(self.config_data)
        self.return_to("main")
        if enable:
            self.change_autostart(True)

    def update_platform(self) -> str | None:
        # The shared checker only knows the Linux bundles (it would fall back to
        # KNULLI here); windows/update.py checks for the Windows zip instead.
        return None

    # Shared helpers --------------------------------------------------------

    def selected_label(self) -> str:
        labels = self.current_labels()
        return labels[self.selected_index] if 0 <= self.selected_index < len(labels) else ""

    def flash(self, text: str, seconds: float = MESSAGE_SECONDS) -> None:
        self.message = (text, time.monotonic() + seconds)

    def open_view(self, view: str, from_view: str | None = None) -> None:
        self.save_view_position(from_view or self.view)
        self.view = view
        self.restore_view_position(view)

    def return_to(self, view: str) -> None:
        self.save_view_position(self.view)
        self.view = view
        self.restore_view_position(view)
        if view == "main":
            self.refresh_main_menu_state(force=True)
        elif view == "cached_games":
            self.refresh_cached_games()

    # Input and drawing for the on-screen keyboard -------------------------

    def render(self) -> None:
        self.start_update_check()
        self.show_update_found_by_check()
        if self.view == KEYBOARD_VIEW and self.keyboard is not None:
            self.render_keyboard()
            return
        super().render()

    def handle_events(self) -> None:
        """The shared loop plus the mouse; the on-screen keyboard takes typed
        text instead of navigation keys."""
        for event in self.pygame.event.get():
            if event.type == self.pygame.QUIT:
                self.running = False
                return
            if self.handle_mouse_event(event):
                continue
            if event.type == self.pygame.KEYDOWN:
                if self.view == KEYBOARD_VIEW:
                    self.keyboard_handle_event(event)
                else:
                    self.handle_key(event.key)
            if not self.running:
                return

    def handle_raw_input(self) -> None:
        if self.view != KEYBOARD_VIEW:
            super().handle_raw_input()
            return
        for key in read_keys(self.input_handles, self.last_key_press):
            if self.view != KEYBOARD_VIEW:
                break
            self.keyboard_handle_code(key)

    def watched_folder_status(self, folder: str) -> str:
        checked = watch_folders.last_scans(self.storage).get(watch_folders.normalize_folder(folder))
        if not checked:
            return "Not checked yet. It's scanned once no game has been played for 5 minutes."
        when = time.strftime("%Y-%m-%d %H:%M", time.localtime(checked / 1000))
        return f"Last checked {when}. Checked again every 30 minutes while the proxy runs."

    # Smart Cache in its own process (background.py), so the menu stays
    # responsive and can be closed while it runs, as on Android.
    def start_smart_cache(self) -> None:
        if self.view == "smart_cache_prompt":
            self.view = "main"
            self.restore_view_position("main")
        if windows_background.start():
            self.flash("Smart Cache is running in the background. You can close the menu.", 4)
        else:
            self.flash("Smart Cache is already running")

    def item_positions(self, items: list[str], start_y: int, gap: int) -> list[int]:
        """Spacing for the Windows layouts; the shared one puts its gaps at fixed
        rows of the Linux screens."""
        if self.view == "cached_games":
            rows = self.cached_game_rows()
            breaks = {
                index
                for index, row in enumerate(rows)
                if row.kind == "header" or row.label == "Clear cache"
            }
        elif self.view == "file_browser" and not self.at_drive_list:
            kinds = [kind for kind, _ in self.file_browser_rows()]
            breaks = {kinds.index("parent")} if "parent" in kinds and kinds[0] == "add_folder" else set()
        elif self.view == "win_history":
            breaks = {index for index in range(2, len(items)) if index % 2 == 0}
        else:
            return super().item_positions(items, start_y, gap)
        positions = []
        y = start_y
        for index in range(len(items)):
            if index in breaks:
                y += GROUP_GAP
            positions.append(y)
            y += gap
        return positions

    # View dispatch ---------------------------------------------------------

    def labels(self, running: bool) -> list[str]:
        if self.view == "file_browser":
            return self.file_browser_labels()
        if self.view == "win_watched":
            return [*watch_folders.watched_folders(self.config_data), BACK]
        if self.view == "win_watched_actions":
            return [UNWATCH_FOLDER, BACK]
        if self.view == "win_history":
            labels = []
            for entry in self.awards_history:
                labels.extend([entry.game_title, entry.detail_text])
            if self.awards_history:
                labels.append(CLEAR_HISTORY)
            labels.append(BACK)
            return labels
        if self.view == "win_history_clear_confirm":
            return ["YES", "NO"]
        if self.view == EXIT_CONFIRM_VIEW:
            return [MINIMIZE_TO_TRAY, EXIT_COMPLETELY, CANCEL]
        if self.view == AUTOSTART_ASK_VIEW:
            return ["Yes, start with Windows", "No thanks"]
        if self.view == SETTINGS_VIEW:
            return self.settings_labels()
        if self.view == STEAM_VIEW:
            return self.steam_labels()
        if self.view in (CLEAR_CACHE_CONFIRM_VIEW, CLEAR_DATABASE_CONFIRM_VIEW, CONSOLE_REMOVE_CONFIRM_VIEW):
            return ["YES", "NO"]
        if self.view == "cached_games":
            return self.cached_games_labels()
        if self.view == CONSOLE_ACTIONS_VIEW:
            return self.console_actions_labels()
        if self.view == "game_actions":
            return self.game_actions_labels()
        if self.view == LOGIN_PROGRESS_VIEW:
            return self.login_progress_labels()
        if self.view == EMULATORS_VIEW:
            return self.emulators_labels()
        if self.view == SUPPORT_VIEW:
            return self.support_labels()
        if self.view == SUPPORT_AMOUNTS_VIEW:
            return self.support_amount_labels()
        if self.view == SUPPORT_DELIVERY_VIEW:
            return [SUPPORT_OPEN_IN_BROWSER, SUPPORT_EMAIL_LINK, BACK]
        if self.view == HELP_VIEW:
            return self.help_labels()
        if self.view == UPDATE_VIEW:
            return self.update_labels()
        if self.view == EMULATOR_ACTIONS_VIEW:
            return self.emulator_actions_labels()
        if self.view == SEND_LOGS_DETAILS_VIEW:
            return [SEND_LOGS_ONLY, SEND_LOGS_WITH_DETAILS, CANCEL]

        labels = super().labels(running)
        if self.view == "main":
            # As in the Android app, autostart and usage stats live in Settings.
            labels = [label for label in labels if label not in MOVED_TO_SETTINGS]
            if setting_enabled(self.config_data, HIDE_SUPPORT_KEY):
                labels = [label for label in labels if label != "Support me"]
            anchor = next((label for label in ("Support me", "Send Logs") if label in labels), None)
            index = labels.index(anchor) if anchor else len(labels) - 1
            labels[index:index] = [EMULATORS_LABEL, WATCHED_FOLDERS_LABEL, AWARDS_HISTORY_LABEL, SETTINGS_LABEL]
            send_logs = labels.index("Send Logs") if "Send Logs" in labels else len(labels) - 1
            labels.insert(send_logs, HELP_LABEL)
            if not self.main_logged_in:
                # Android offers the login up front; the proxy also picks it up from online play.
                labels.insert(1, LOGIN_LABEL)
            update = self.update_label()
            if update:
                labels.insert(1, update)
        return labels

    def title_for_view(self) -> str:
        titles = {
            "win_watched": "Watched Folders",
            "win_watched_actions": "Watched Folder",
            "win_history": "Awards History",
            "win_history_clear_confirm": "Clear Award History?",
            EXIT_CONFIRM_VIEW: "Close the Menu?",
            AUTOSTART_ASK_VIEW: "Start with Windows?",
            SETTINGS_VIEW: "Settings",
            STEAM_VIEW: "Add to Steam",
            CLEAR_CACHE_CONFIRM_VIEW: "Clear Cache?",
            CLEAR_DATABASE_CONFIRM_VIEW: "Clear Database?",
            CONSOLE_REMOVE_CONFIRM_VIEW: "Remove Games?",
            LOGIN_PROGRESS_VIEW: "RetroAchievements Login",
            SEND_LOGS_DETAILS_VIEW: "Send Logs",
            EMULATORS_VIEW: "Emulators",
            SUPPORT_VIEW: "Support RAOfflineProxy",
            SUPPORT_AMOUNTS_VIEW: "Monthly" if self.support_frequency == "monthly" else "One Time",
            SUPPORT_DELIVERY_VIEW: self.support_amount[0] if self.support_amount else "Support",
            HELP_VIEW: "Help & About",
            UPDATE_VIEW: "Update Available",
        }
        if self.view == EMULATOR_ACTIONS_VIEW and self.active_emulator is not None:
            return self.active_emulator.name
        if self.view == "file_browser" and self.browser_pick_kind is not None:
            return f"Find {self.browser_pick_kind.name}"
        if self.view == CONSOLE_ACTIONS_VIEW:
            from .games import console_name

            return console_name(self.active_console_id)
        return titles.get(self.view) or super().title_for_view()

    def status_text(self, running: bool) -> str:
        if self.view == "file_browser" and self.at_drive_list:
            return "Choose a drive"
        if self.view == "win_watched":
            folders = watch_folders.watched_folders(self.config_data)
            if not folders:
                return "No folders yet. Use Add ROM to browse to a folder and watch it."
            if 0 <= self.selected_index < len(folders):
                return self.watched_folder_status(folders[self.selected_index])
            return (
                f"WATCHED: {len(folders)}. New ROMs are cached every 30 minutes while the proxy "
                "runs, once no game has been played for 5 minutes."
            )
        if self.view == "win_watched_actions":
            return self.active_watched_folder or ""
        if self.view == "win_history":
            if not self.awards_history:
                return "No offline awards have been synced yet."
            return f"SYNCED: {len(self.awards_history)}"
        if self.view == "win_history_clear_confirm":
            return "This removes all synced offline awards from history."
        if self.view == AUTOSTART_ASK_VIEW:
            return (
                "Start RAOfflineProxy when you sign in to Windows? It runs quietly in the "
                "background with an icon by the clock, so offline achievements just work. "
                "Windows asks for admin permission once, so it also starts in Xbox mode. "
                "You can change this any time in Settings."
            )
        if self.view == EXIT_CONFIRM_VIEW:
            return (
                "Minimize keeps the proxy running, with its icon by the clock. "
                "Exit completely stops the proxy and puts your emulators back to normal. "
                "Change what B does in Settings."
            )
        if self.view == SETTINGS_VIEW:
            return self.settings_status()
        if self.view == STEAM_VIEW:
            return self.steam_status()
        if self.view == CLEAR_CACHE_CONFIRM_VIEW:
            return "This removes all cached games and cached RetroAchievements data."
        if self.view == CLEAR_DATABASE_CONFIRM_VIEW:
            return self.clear_database_warning()
        if self.view == SUPPORT_VIEW:
            return (
                "RAOfflineProxy is free and open source, built and maintained by one person "
                "in their spare time. If it's been useful to you, a small donation helps keep it going."
            )
        if self.view == SUPPORT_DELIVERY_VIEW:
            return "Pay now in your browser, or get the payment link by email to pay from any device."
        if self.view == HELP_VIEW:
            return f"RAOfflineProxy {self.app_version_text()} for Windows"
        if self.view == UPDATE_VIEW and self.update_info is not None:
            return f"Version {self.update_info.latest_version} is available. Installing restarts the proxy."
        if self.view == EMULATORS_VIEW:
            return self.emulators_status()
        if self.view == EMULATOR_ACTIONS_VIEW and self.active_emulator is not None:
            entry = windows_emulators.emulator_state(self.config_data).get(self.active_emulator.key)
            return entry["config"] if entry else "Not found yet."
        if self.view == LOGIN_PROGRESS_VIEW:
            return self.login_status
        if self.view == SEND_LOGS_DETAILS_VIEW:
            return "This uploads recent logs to help diagnose an issue. Adding details sends them to the developer with your log ID."
        if self.view == CONSOLE_ACTIONS_VIEW:
            return f"{len(self.console_games())} cached games"
        if self.view == CONSOLE_REMOVE_CONFIRM_VIEW:
            return f"This removes all {len(self.console_games())} cached games for this console."
        if self.view == "cached_games":
            return self.cached_games_status(super().status_text(running))
        if self.view == "game_actions" and self.active_game is not None:
            return self.game_actions_status(super().status_text(running))
        return super().status_text(running)

    def bottom_hint_text(self) -> str | None:
        if self.view in ("win_history_clear_confirm", CLEAR_CACHE_CONFIRM_VIEW, CLEAR_DATABASE_CONFIRM_VIEW, CONSOLE_REMOVE_CONFIRM_VIEW):
            return self.confirm_cancel_hint("confirm", "cancel")
        if self.view in ("win_watched", "win_watched_actions", "win_history", SETTINGS_VIEW, STEAM_VIEW, LOGIN_PROGRESS_VIEW, SEND_LOGS_DETAILS_VIEW, EMULATORS_VIEW, EMULATOR_ACTIONS_VIEW,
                         SUPPORT_VIEW, SUPPORT_AMOUNTS_VIEW, SUPPORT_DELIVERY_VIEW, HELP_VIEW, UPDATE_VIEW):
            return None
        hint = super().bottom_hint_text()
        if self.view == "main" and hint == "Login to RetroAchievements in system settings.":
            return self.login_hint()
        if hint is None and self.view in ("main", "cached_games"):
            return windows_background.status_text()
        return hint

    def activate_selected(self) -> None:
        if self.view == "file_browser":
            self.activate_windows_file_browser()
            return
        if self.view == "win_watched":
            self.activate_watched()
            return
        if self.view == "win_watched_actions":
            self.activate_watched_actions()
            return
        if self.view == "win_history":
            self.activate_history()
            return
        if self.view == "win_history_clear_confirm":
            self.activate_history_clear_confirm()
            return
        if self.view == AUTOSTART_ASK_VIEW:
            self.answer_autostart(self.selected_index == 0)
            return
        if self.view == EXIT_CONFIRM_VIEW:
            label = self.selected_label()
            if label == MINIMIZE_TO_TRAY:
                self.running = False
            elif label == EXIT_COMPLETELY:
                self.exit_completely()
            else:
                self.return_to("main")
            return
        if self.view == SETTINGS_VIEW:
            self.activate_settings()
            return
        if self.view == STEAM_VIEW:
            self.activate_steam()
            return
        if self.view == CLEAR_CACHE_CONFIRM_VIEW:
            self.activate_clear_cache_confirm()
            return
        if self.view == CLEAR_DATABASE_CONFIRM_VIEW:
            self.activate_clear_database_confirm()
            return
        if self.view == CONSOLE_ACTIONS_VIEW:
            self.activate_console_actions()
            return
        if self.view == LOGIN_PROGRESS_VIEW:
            self.finish_login()
            return
        if self.view == SEND_LOGS_DETAILS_VIEW:
            self.activate_send_logs_details()
            return
        if self.view == EMULATORS_VIEW:
            self.activate_emulators()
            return
        if self.view == SUPPORT_VIEW:
            self.activate_support()
            return
        if self.view == SUPPORT_AMOUNTS_VIEW:
            self.activate_support_amount()
            return
        if self.view == SUPPORT_DELIVERY_VIEW:
            self.activate_support_delivery()
            return
        if self.view == HELP_VIEW:
            self.activate_help()
            return
        if self.view == UPDATE_VIEW:
            self.activate_update()
            return
        if self.view == EMULATOR_ACTIONS_VIEW:
            self.activate_emulator_actions()
            return
        if self.view == CONSOLE_REMOVE_CONFIRM_VIEW:
            self.activate_console_remove_confirm()
            return

        if self.view == "main":
            label = self.selected_label()
            if label == WATCHED_FOLDERS_LABEL:
                self.config_data = load_config()
                self.open_view("win_watched", "main")
                return
            if label == "Support me":
                self.open_support()
                return
            if label == HELP_LABEL:
                self.open_view(HELP_VIEW, "main")
                self.reset_selection()
                return
            if label.startswith("Update available"):
                self.open_view(UPDATE_VIEW, "main")
                self.reset_selection()
                return
            if label == EMULATORS_LABEL:
                self.open_emulators()
                return
            if label == LOGIN_LABEL:
                self.start_login()
                return
            if label == SETTINGS_LABEL:
                self.open_settings()
                return
            if label == AWARDS_HISTORY_LABEL:
                self.awards_history = windows_history.list_synced_awards(self.storage)
                self.open_view("win_history", "main")
                return

        super().activate_selected()

    def go_back(self) -> None:
        if self.view == "main":
            # On the handhelds, back at the top level exits the app. On a PC the
            # menu sits beside games, so what B does is a setting, asking by
            # default (Exit Menu still just closes the window).
            action = back_action(load_config())
            if action == "minimize":
                self.running = False
            elif action == "exit":
                self.exit_completely()
            else:
                self.open_view(EXIT_CONFIRM_VIEW, "main")
                self.reset_selection()
            return
        if self.view == EXIT_CONFIRM_VIEW:
            self.return_to("main")
            return
        if self.view == AUTOSTART_ASK_VIEW:
            self.answer_autostart(False)  # B means not now; it isn't asked again
            return
        if self.view == "file_browser":
            self.browser_go_up()
            return
        if self.view in ("win_watched", "win_history", SETTINGS_VIEW):
            self.return_to("main")
            return
        if self.view in (CLEAR_CACHE_CONFIRM_VIEW, CLEAR_DATABASE_CONFIRM_VIEW, STEAM_VIEW):
            self.return_to(SETTINGS_VIEW)
            return
        if self.view == LOGIN_PROGRESS_VIEW:
            self.finish_login()
            return
        if self.view == SUPPORT_AMOUNTS_VIEW:
            self.return_to(SUPPORT_VIEW)
            return
        if self.view == SUPPORT_DELIVERY_VIEW:
            self.return_to(SUPPORT_AMOUNTS_VIEW)
            return
        if self.view in (SEND_LOGS_DETAILS_VIEW, EMULATORS_VIEW, SUPPORT_VIEW, HELP_VIEW, UPDATE_VIEW):
            self.return_to("main")
            return
        if self.view == EMULATOR_ACTIONS_VIEW:
            self.active_emulator = None
            self.return_to(EMULATORS_VIEW)
            return
        if self.view in (CONSOLE_ACTIONS_VIEW, CONSOLE_REMOVE_CONFIRM_VIEW):
            self.active_console_id = None
            self.return_to("cached_games")
            return
        if self.view == "win_watched_actions":
            self.active_watched_folder = None
            self.return_to("win_watched")
            return
        if self.view == "win_history_clear_confirm":
            self.return_to("win_history")
            return
        super().go_back()

    # File browser: any drive and folder, like the Android folder picker ------

    def open_file_browser(self) -> None:
        self.save_view_position("cached_games")
        config_data = load_config()
        start = None
        for key in (LAST_BROWSER_DIR_KEY, "rom_root"):
            candidate = config_data.get(key)
            if candidate and Path(str(candidate)).is_dir():
                start = Path(str(candidate))
                break
        self.browser_root = None
        self.view = "file_browser"
        if start is None:
            self.show_drive_list()
        else:
            self.enter_browser_dir(start, restore=True)

    def show_drive_list(self) -> None:
        self.save_browser_position()
        self.at_drive_list = True
        self.browser_dir = None
        self.drives = list_drives()
        self.reset_selection()

    def enter_browser_dir(self, path: Path, restore: bool) -> None:
        try:
            self.at_drive_list = False
            self.set_browser_dir(path, restore=restore)
        except OSError as exc:
            # An unplugged drive or an unreachable network share.
            self.flash(f"Can't open {path}: {exc.strerror or exc}", ERROR_SECONDS)
            self.show_drive_list()
            return
        self.remember_browser_dir(path)

    def set_browser_dir(self, path: Path, restore: bool = False) -> None:
        self.browser_dir = path
        kind = self.browser_pick_kind
        self.browser_entries = list_folder(path, (lambda name: name.lower() in kind.exe_names) if kind else None)
        if restore:
            self.restore_browser_position(path)
            return
        self.reset_selection()

    def browser_has_cacheable_files(self) -> bool:
        # Any folder below a drive root can be cached or watched, as with the
        # Android folder picker; a folder without ROMs just finds none. Checking
        # first would mean walking the whole tree.
        return self.browser_dir is not None and self.browser_dir.parent != self.browser_dir

    def remember_browser_dir(self, path: Path) -> None:
        if self.browser_pick_kind is not None:
            return
        if self.config_data.get(LAST_BROWSER_DIR_KEY) != str(path):
            self.config_data = load_config()
            self.config_data[LAST_BROWSER_DIR_KEY] = str(path)
            save_config(self.config_data)

    def browser_is_watched(self) -> bool:
        if self.browser_dir is None:
            return False
        folder = watch_folders.normalize_folder(self.browser_dir)
        return folder in watch_folders.watched_folders(self.config_data)

    def file_browser_rows(self) -> list[tuple[str, object]]:
        """(kind, value) per row. Selection dispatches on the kind, never the
        label, so a folder named "Cancel" or "Add folder" just opens."""
        if self.at_drive_list:
            return [("drive", drive) for drive in self.drives] + [("cancel", None)]
        if self.browser_dir is None:
            return [("cancel", None)]
        rows: list[tuple[str, object]] = []
        if self.browser_pick_kind is None and self.browser_has_cacheable_files():
            rows.append(("add_folder", None))
            rows.append(("watch", None))
        rows.append(("parent", None))
        rows.extend(("entry", entry) for entry in self.browser_entries)
        rows.append(("cancel", None))
        return rows

    def file_browser_labels(self) -> list[str]:
        labels = []
        for kind, value in self.file_browser_rows():
            if kind in ("drive", "entry"):
                labels.append(str(value) if kind == "drive" else value.name)
            elif kind == "watch":
                labels.append(UNWATCH_FOLDER if self.browser_is_watched() else WATCH_FOLDER)
            else:
                labels.append({"add_folder": ADD_FOLDER, "parent": PARENT, "cancel": CANCEL}[kind])
        return labels

    def activate_windows_file_browser(self) -> None:
        rows = self.file_browser_rows()
        if not 0 <= self.selected_index < len(rows):
            return
        kind, value = rows[self.selected_index]

        if kind == "cancel":
            self.save_browser_position()
            self.leave_browser()
        elif kind == "drive":
            self.enter_browser_dir(value, restore=True)
        elif kind == "add_folder":
            self.start_folder_cache_for_browser_dir()
        elif kind == "watch":
            self.toggle_watch_browser_dir()
        elif kind == "parent":
            self.browser_go_up()
        elif value.is_dir():
            self.save_browser_position()
            self.enter_browser_dir(value, restore=True)
        elif self.browser_pick_kind is not None:
            self.choose_emulator_exe(value)
        else:
            self.start_single_rom_cache(value)

    def exit_completely(self) -> None:
        """Stops the proxy (which puts the emulator configs back), closes the
        tray icon, then the menu."""
        from .tray import QUIT_REQUEST_FILE

        if self.proxy_running():
            self.stop_proxy()
        QUIT_REQUEST_FILE.parent.mkdir(parents=True, exist_ok=True)
        QUIT_REQUEST_FILE.touch()
        self.running = False

    def leave_browser(self) -> None:
        self.at_drive_list = False
        if self.browser_pick_kind is not None:
            self.browser_pick_kind = None
            self.return_to("win_emulators")
            return
        self.return_to("cached_games")

    def browser_go_up(self) -> None:
        if self.at_drive_list or self.browser_dir is None:
            self.leave_browser()
            return
        self.save_browser_position()
        if self.browser_dir.parent == self.browser_dir:
            self.show_drive_list()
            return
        self.enter_browser_dir(self.browser_dir.parent, restore=True)

    def toggle_watch_browser_dir(self) -> None:
        if self.browser_dir is None:
            return
        self.config_data = load_config()
        if self.browser_is_watched():
            watch_folders.unwatch_folder(self.config_data, self.storage, self.browser_dir)
            self.flash("Stopped watching folder")
        else:
            watch_folders.watch_folder(self.config_data, self.browser_dir)
            self.flash("Watching folder: new ROMs are cached every 30 minutes")

    # Watched folders --------------------------------------------------------

    def activate_watched(self) -> None:
        label = self.selected_label()
        if label == BACK:
            self.return_to("main")
            return
        self.active_watched_folder = label
        self.open_view("win_watched_actions")
        self.reset_selection()

    def activate_watched_actions(self) -> None:
        label = self.selected_label()
        if label == UNWATCH_FOLDER and self.active_watched_folder is not None:
            self.config_data = load_config()
            watch_folders.unwatch_folder(self.config_data, self.storage, self.active_watched_folder)
            self.flash("Stopped watching folder")
        self.active_watched_folder = None
        self.return_to("win_watched")

    # Awards history ---------------------------------------------------------

    def activate_history(self) -> None:
        label = self.selected_label()
        if label == BACK:
            self.return_to("main")
            return
        if label == CLEAR_HISTORY:
            if any(
                award.get("status", PENDING_AWARD_STATUS_PENDING) == PENDING_AWARD_STATUS_PENDING
                for award in self.storage.get_pending_awards()
            ):
                self.flash("Pending awards must be synced first", ERROR_SECONDS)
                return
            self.open_view("win_history_clear_confirm")
            self.reset_selection()

    def activate_history_clear_confirm(self) -> None:
        if self.selected_label() == "YES":
            windows_history.clear_history()
            self.awards_history = []
            self.flash("Award history cleared")
        self.return_to("win_history")

