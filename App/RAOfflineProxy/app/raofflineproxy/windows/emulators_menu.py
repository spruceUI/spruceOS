from __future__ import annotations

"""Emulators screen for the Windows menu, like the Android app's enabled
emulators selector: each detected emulator on or off, detect again, or browse
to an exe detection missed. Mixed into WindowsMenuSession."""

import threading
from pathlib import Path

from . import emulators as windows_emulators
from ..config import load_config, save_config
from ..menu_sdl import ERROR_SECONDS

EMULATORS_LABEL = "Emulators"
EMULATORS_VIEW = "win_emulators"
EMULATOR_ACTIONS_VIEW = "win_emulator_actions"
DETECT = "Detect emulators"
BACK = "Back"


class EmulatorsMixin:
    def emulator_rows(self) -> list[tuple[str, object]]:
        state = windows_emulators.emulator_state(self.config_data)
        rows = []
        for kind in windows_emulators.KINDS:
            entry = state.get(kind.key)
            if entry is None:
                value = "Not found"
            else:
                value = "On" if entry.get("enabled", True) else "Off"
            rows.append((f"{kind.name}: {value}", kind))
        rows.append((DETECT, None))
        rows.append((BACK, None))
        return rows

    def emulators_labels(self) -> list[str]:
        return [label for label, _ in self.emulator_rows()]

    def emulators_status(self) -> str:
        if self.emulator_detect_thread is not None and self.emulator_detect_thread.is_alive():
            return "Looking for RetroArch, Dolphin and PPSSPP..."
        rows = self.emulator_rows()
        if 0 <= self.selected_index < len(rows) and rows[self.selected_index][1] is not None:
            kind = rows[self.selected_index][1]
            entry = windows_emulators.emulator_state(self.config_data).get(kind.key)
            return entry["exe"] if entry else f"{kind.name} wasn't found. Select it to browse to {kind.exe_names[0]}."
        return "The proxy points each emulator that's on at itself while it runs."

    def open_emulators(self) -> None:
        self.config_data = load_config()
        self.open_view(EMULATORS_VIEW, "main")

    def emulators_locked(self) -> bool:
        # Changing an emulator while the proxy has it patched would strand the
        # patch, as on Android, where the selector is disabled while it runs.
        if self.proxy_running():
            self.flash("Stop the proxy to change emulators", ERROR_SECONDS)
            return True
        return False

    def activate_emulators(self) -> None:
        label, kind = self.emulator_rows()[self.selected_index]
        if label == BACK:
            self.return_to("main")
        elif label == DETECT:
            self.start_emulator_detection()
        elif not self.emulators_locked():
            self.active_emulator = kind
            self.open_view(EMULATOR_ACTIONS_VIEW)
            self.reset_selection()

    def emulator_actions_labels(self) -> list[str]:
        kind = self.active_emulator
        entry = windows_emulators.emulator_state(self.config_data).get(kind.key)
        labels = []
        if entry is not None:
            labels.append("Turn off" if entry.get("enabled", True) else "Turn on")
        labels.append(f"Browse to {kind.exe_names[0]}...")
        labels.append(BACK)
        return labels

    def activate_emulator_actions(self) -> None:
        label = self.selected_label()
        kind = self.active_emulator
        if label in ("Turn off", "Turn on"):
            self.config_data = load_config()
            windows_emulators.set_emulator(self.config_data, kind, enabled=label == "Turn on")
            save_config(self.config_data)
            self.flash(f"{kind.name} turned {'on' if label == 'Turn on' else 'off'}")
            self.return_to(EMULATORS_VIEW)
        elif label.startswith("Browse to"):
            self.browser_pick_kind = kind
            self.browser_root = None
            self.view = "file_browser"
            entry = windows_emulators.emulator_state(self.config_data).get(kind.key)
            start = Path(entry["exe"]).parent if entry else None
            if start is not None and start.is_dir():
                self.enter_browser_dir(start, restore=False)
            else:
                self.show_drive_list()
        else:
            self.return_to(EMULATORS_VIEW)

    def choose_emulator_exe(self, exe: Path) -> None:
        kind = self.browser_pick_kind
        self.config_data = load_config()
        windows_emulators.set_emulator(self.config_data, kind, exe=exe, enabled=True)
        save_config(self.config_data)
        self.flash(f"{kind.name} set to {exe.parent}")
        self.browser_pick_kind = None
        self.at_drive_list = False
        self.return_to(EMULATORS_VIEW)

    def start_emulator_detection(self) -> None:
        if self.emulators_locked():
            return
        if self.emulator_detect_thread is not None and self.emulator_detect_thread.is_alive():
            return

        def worker() -> None:
            try:
                windows_emulators.detect_and_save()
                self.config_data = load_config()
                found = len(windows_emulators.emulator_state(self.config_data))
                self.flash(f"Found {found} of {len(windows_emulators.KINDS)} emulators")
            except Exception as exc:
                self.flash(f"Detection failed: {exc}", ERROR_SECONDS)

        self.emulator_detect_thread = threading.Thread(target=worker, daemon=True)
        self.emulator_detect_thread.start()
