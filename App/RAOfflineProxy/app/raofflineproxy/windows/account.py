from __future__ import annotations

"""RetroAchievements login and Send Logs with details for the Windows menu,
as in the Android app, plus the Windows device metadata sent with logs and
usage stats. Mixed into WindowsMenuSession."""

import json
import logging
import platform
import threading
import urllib.request

from ..auth import login_and_cache_token
from ..config import APP_VERSION, FALLBACK_USER_AGENT, load_config
from ..log_uploader import REQUEST_TIMEOUT_SECONDS, upload_logs
from ..menu_sdl import ERROR_SECONDS
from ..network import configured_ssl_context

LOGGER = logging.getLogger("raofflineproxy")

# The endpoint the website's support form and the Android app post to, so a
# report with details lands in the same place.
SUPPORT_SUBMIT_URL = "https://ud63psmdb5.execute-api.eu-central-1.amazonaws.com/support/submit"

LOGIN_LABEL = "Log in to RetroAchievements"
LOGIN_PROGRESS_VIEW = "win_login_progress"
SEND_LOGS_DETAILS_VIEW = "win_send_logs_details"
SEND_LOGS_ONLY = "Send logs only"
SEND_LOGS_WITH_DETAILS = "Add details and send"


# Device metadata --------------------------------------------------------------------


def _bios_value(name: str) -> str | None:
    import winreg

    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"HARDWARE\DESCRIPTION\System\BIOS") as key:
            value, _ = winreg.QueryValueEx(key, name)
    except OSError:
        return None
    value = str(value).strip()
    return value if value and value.lower() not in ("default string", "to be filled by o.e.m.") else None


def device_label() -> str:
    """The PC or handheld model, e.g. "Micro-Star International Claw 8 AI+"."""
    parts = [_bios_value("SystemManufacturer"), _bios_value("SystemProductName")]
    label = " ".join(part for part in parts if part)
    return label or platform.node() or "Windows PC"


def os_version() -> str:
    import winreg

    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows NT\CurrentVersion") as key:
            display, _ = winreg.QueryValueEx(key, "DisplayVersion")
            build, _ = winreg.QueryValueEx(key, "CurrentBuild")
        # The registry ProductName still says "Windows 10" on Windows 11.
        name = "Windows 11" if int(build) >= 22000 else "Windows 10"
        return f"{name} {display} (build {build})"
    except (OSError, ValueError):
        return platform.platform()


def metadata_overrides(config_data: dict) -> dict:
    """What log_uploader.device_metadata reports differently on Windows."""
    from ..state import load_patch_state

    overrides: dict = {
        "system": "Windows",
        "os": "Windows",
        "device": device_label(),
        "os_version": os_version(),
    }
    # The shared list checks the default RetroArch location rather than the
    # configured one, and has no Dolphin, so it's rebuilt from what the proxy
    # actually patched. The field and names are the shared ones.
    state = load_patch_state() or {}
    emulators = []
    if state.get("cfg_path") and "disabled-emulators" not in str(state["cfg_path"]):
        emulators.append("RetroArch")
    if state.get("dolphin_ini_path"):
        emulators.append("Dolphin")
    if state.get("ppsspp_ini_path"):
        emulators.append("PPSSPP")
    if state.get("pcsx2_ini_path"):
        emulators.append("PCSX2")
    if state.get("duckstation_ini_path"):
        emulators.append("DuckStation")
    if state.get("flycast_cfg_path"):
        emulators.append("Flycast")
    if emulators:
        overrides["emulator"] = emulators
    return overrides


def submit_support_request(log_id: str, email: str, message: str) -> None:
    payload = {
        "email": email,
        "system": "Windows",
        "device": device_label(),
        "os_version": os_version(),
        "app_version": APP_VERSION,
        "log_id": log_id,
        "message": message,
    }
    request = urllib.request.Request(
        SUPPORT_SUBMIT_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS, context=configured_ssl_context()):
        return


def retroarch_account_note(user: str) -> str:
    """The proxy prefers the login saved in RetroArch's config over the one
    from this menu, so say so when RetroArch is signed in as someone else."""
    from ..platform import resolve_retroarch_cfg
    from ..retroarch_cfg import load_retroarch_credentials

    try:
        saved = load_retroarch_credentials(resolve_retroarch_cfg(load_config()))
    except Exception:
        return ""
    other = (saved or {}).get("user")
    if other and other.lower() != user.lower():
        return (
            f" RetroArch is signed in as {other}, and the proxy uses that account while"
            " it is. Sign out of it in RetroArch to use this one."
        )
    return ""


# Menu ---------------------------------------------------------------------------------


class AccountMixin:
    login_user: str = ""
    login_thread: threading.Thread | None = None
    login_status: str = ""
    logs_details: dict | None = None

    # Login: username, then password, then a background login2 --------------------------

    def start_login(self) -> None:
        self.open_keyboard(
            "RetroAchievements Login",
            "Username",
            self.login_username_entered,
            initial=self.login_user,
        )

    def login_username_entered(self, user: str) -> None:
        user = user.strip()
        if not user:
            self.flash("Enter your RetroAchievements username.", ERROR_SECONDS)
            self.start_login()
            return
        self.login_user = user
        self.open_keyboard(
            "RetroAchievements Login",
            f"Password for {user}. It's only sent to RetroAchievements; the proxy keeps the login token.",
            self.login_password_entered,
            secret=True,
        )

    def login_password_entered(self, password: str) -> None:
        if not password:
            self.flash("Enter your RetroAchievements password.", ERROR_SECONDS)
            self.login_username_entered(self.login_user)
            return
        user = self.login_user
        self.login_status = f"Logging in as {user}..."
        self.open_view(LOGIN_PROGRESS_VIEW)
        self.reset_selection()

        def worker() -> None:
            result = login_and_cache_token(
                self.storage, load_config(), {"user": user, "password": password}, FALLBACK_USER_AGENT
            )
            if result is None:
                self.login_status = "Login failed. Check your username and password."
            else:
                self.storage.clear_invalid_token()
                self.login_status = f"Logged in as {result['user']}." + retroarch_account_note(result["user"])

        self.login_thread = threading.Thread(target=worker, daemon=True)
        self.login_thread.start()

    def login_in_progress(self) -> bool:
        return self.login_thread is not None and self.login_thread.is_alive()

    def finish_login(self) -> None:
        if self.login_in_progress():
            return
        self.login_thread = None
        self.return_to("main")

    # Send Logs, optionally with "What happened?" and an email ------------------------

    def activate_send_logs_confirm_selected(self) -> None:
        if self.selected_index == 0:
            self.open_view(SEND_LOGS_DETAILS_VIEW)
            self.reset_selection()
            return
        self.return_to("main")

    def activate_send_logs_details(self) -> None:
        label = self.selected_label()
        if label == SEND_LOGS_ONLY:
            self.start_send_logs()
        elif label == SEND_LOGS_WITH_DETAILS:
            self.logs_details = {}
            self.open_keyboard("Send Logs", "What happened? (required)", self.logs_message_entered)
        else:
            self.return_to("main")

    def logs_message_entered(self, message: str) -> None:
        if not message.strip():
            self.flash("Describe what happened, or cancel and choose Send logs only.", ERROR_SECONDS)
            self.open_keyboard("Send Logs", "What happened? (required)", self.logs_message_entered)
            return
        self.logs_details = {"message": message.strip()}
        self.open_keyboard(
            "Send Logs",
            "Email address (required), so the developer can reply.",
            self.logs_email_entered,
        )

    def logs_email_entered(self, email: str) -> None:
        email = email.strip()
        if "@" not in email or "." not in email.split("@")[-1]:
            self.flash("Enter a valid email address.", ERROR_SECONDS)
            self.open_keyboard(
                "Send Logs",
                "Email address (required), so the developer can reply.",
                self.logs_email_entered,
                initial=email,
            )
            return
        self.logs_details["email"] = email
        self.start_send_logs()

    def start_send_logs(self) -> None:
        from .paths import test_channel

        details = self.logs_details
        self.logs_details = None
        logs_folder = test_channel().get("logs_folder")
        if logs_folder:
            self.save_logs_to_folder(logs_folder, details)
            return
        if not details:
            super().start_send_logs()
            return

        self.storage_corruption_active = False
        self.log_upload_progress_text = "Uploading logs..."
        self.log_upload_result = None
        self.view = "send_logs_progress"
        self.reset_selection()

        def worker() -> None:
            try:
                upload_id = upload_logs()
                self.log_upload_progress_text = "Sending your details..."
                try:
                    submit_support_request(upload_id, details["email"], details["message"])
                    self.log_upload_result = (True, upload_id)
                except Exception as exc:
                    LOGGER.warning("Support request failed: %s", exc)
                    self.log_upload_result = (True, f"{upload_id} (details not sent: {exc})")
            except Exception as exc:
                self.log_upload_result = (False, str(exc))
            finally:
                self.log_upload_progress_text = None
                if self.view == "send_logs_progress":
                    self.view = "send_logs_result"
                    self.reset_selection()

        self.log_upload_thread = threading.Thread(target=worker, daemon=True)
        self.log_upload_thread.start()

    def save_logs_to_folder(self, folder: str, details: dict | None) -> None:
        """Test builds: the same redacted log zip Send Logs would upload, saved to
        the test channel's folder with the details and device info beside it."""
        import json
        import time
        from pathlib import Path

        from ..log_uploader import _read_redacted_log_files, _zip_logs, device_metadata

        self.storage_corruption_active = False
        self.log_upload_progress_text = "Saving logs..."
        self.log_upload_result = None
        self.view = "send_logs_progress"
        self.reset_selection()

        def worker() -> None:
            try:
                files = _read_redacted_log_files()
                files["device.json"] = json.dumps(device_metadata(), indent=2)
                if details:
                    files["details.txt"] = f"Email: {details.get('email')}\n\n{details.get('message')}\n"
                name = f"{platform.node()}-{time.strftime('%Y%m%d-%H%M%S')}.zip"
                target = Path(folder) / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(_zip_logs(files))
                self.log_upload_result = (True, f"saved to {target}")
            except Exception as exc:
                self.log_upload_result = (False, f"couldn't save to {folder}: {exc}")
            finally:
                self.log_upload_progress_text = None
                if self.view == "send_logs_progress":
                    self.view = "send_logs_result"
                    self.reset_selection()

        self.log_upload_thread = threading.Thread(target=worker, daemon=True)
        self.log_upload_thread.start()

    def login_hint(self) -> str:
        return "Not logged in yet."

    def login_progress_labels(self) -> list[str]:
        return [] if self.login_in_progress() else ["Back"]
