from __future__ import annotations

"""Support, links and updates for the Windows menu, as in the Android app:
monthly or one-time support paid in the browser or by an emailed link, Ko-fi,
Manage subscription, contact, privacy policy and documentation, and the update
prompt. On a PC these open in the browser rather than as the Linux menu's QR
codes. Mixed into WindowsMenuSession."""

import json
import threading
import urllib.request
import webbrowser

from . import update as windows_update
from ..config import APP_VERSION, PROXY_UA_TAG, load_config
from ..log_uploader import REQUEST_TIMEOUT_SECONDS
from ..menu_sdl import ERROR_SECONDS
from ..network import configured_ssl_context
from .settings import UPDATE_CHECK_KEY, setting_enabled

SUPPORT_VIEW = "win_support"
SUPPORT_AMOUNTS_VIEW = "win_support_amounts"
SUPPORT_DELIVERY_VIEW = "win_support_delivery"
UPDATE_VIEW = "win_update"
HELP_VIEW = "win_help"
HELP_LABEL = "Help & about"

SUPPORT_PAYMENT_BASE_URL = "https://ud63psmdb5.execute-api.eu-central-1.amazonaws.com/support"
KOFI_URL = "https://ko-fi.com/misantronic"
CONTACT_URL = "https://forms.gle/XPRfWe2hAqzYy3JX9"
PRIVACY_URL = "https://raofflineproxy.com/privacy-policy.html"
DOCS_URL = "https://raofflineproxy.com/introduction.html"

# The Android app's DonationLinks: (label, Stripe link, amount in cents).
MONTHLY_AMOUNTS = [
    ("$1 / month", "https://buy.stripe.com/7sYcN7ghBd108DZ5xlbwk08", 100),
    ("$3 / month", "https://buy.stripe.com/6oUaEZc1l6CC3jFe3Rbwk09", 300),
    ("$5 / month", "https://buy.stripe.com/3cIeVf5CX4uubQb8Jxbwk0a", 500),
    ("$8 / month", "https://buy.stripe.com/aFafZj1mH7GG8DZbVJbwk0b", 800),
    ("$10 / month", "https://buy.stripe.com/6oU8wRc1lf989I31h5bwk0c", 1000),
    ("$15 / month", "https://buy.stripe.com/5kQ3cxe9t2mm2fB0d1bwk0d", 1500),
]
ONE_TIME_AMOUNTS = [
    ("$3", "https://buy.stripe.com/3cIfZj9Tdgdc07t6Bpbwk0g", 300),
    ("$5", "https://buy.stripe.com/8x2eVf7L53qq4nJe3Rbwk0h", 500),
    ("$8", "https://buy.stripe.com/dRmaEZ0iD8KK07te3Rbwk0i", 800),
    ("$10", "https://buy.stripe.com/eVqbJ33uP0eeaM77Ftbwk0j", 1000),
    ("$15", "https://buy.stripe.com/eVq14p7L55yy7zV2l9bwk0k", 1500),
]

MONTHLY = "Monthly"
ONE_TIME = "One time"
KOFI = "Ko-fi"
MANAGE = "Manage subscription"
OPEN_IN_BROWSER = "Pay in the browser"
EMAIL_LINK = "Email me a link"
BACK = "Back"
# The User-Agent RetroAchievements accepts, which the support backend presents
# when it checks the login on the app's behalf (as the Android app sends).
RA_USER_AGENT = f"{PROXY_UA_TAG}"


def post_support(path: str, body: dict) -> dict:
    request = urllib.request.Request(
        f"{SUPPORT_PAYMENT_BASE_URL}/{path}",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS, context=configured_ssl_context()) as response:
        return json.loads(response.read().decode("utf-8") or "{}")


UPDATE_RECHECK_SECONDS = 60


class SupportMixin:
    support_frequency: str = "monthly"
    support_amount: tuple | None = None
    support_has_subscription: bool | None = None
    update_info = None
    # When the last check started. A menu left open (or minimized to the tray)
    # checks again every so often, as the tray does; check() keeps to its own
    # interval for going online, so this mostly reads the saved result.
    update_checked_at: float | None = None
    update_download_thread: threading.Thread | None = None

    def open_in_browser(self, url: str) -> None:
        webbrowser.open(url)
        self.flash("Opened in your browser")

    def credentials(self) -> dict | None:
        try:
            return self.storage.load_login_credentials()
        except Exception:
            return None

    # Support ---------------------------------------------------------------------

    def open_support(self) -> None:
        self.open_view(SUPPORT_VIEW, "main")
        credentials = self.credentials()
        if credentials is None or self.support_has_subscription is not None:
            return

        def worker() -> None:
            try:
                result = post_support(
                    "subscription/status",
                    {"username": credentials["user"], "token": credentials["token"], "userAgent": RA_USER_AGENT},
                )
                self.support_has_subscription = bool(result.get("hasActiveSubscription"))
            except Exception:
                self.support_has_subscription = False

        threading.Thread(target=worker, daemon=True).start()

    def support_labels(self) -> list[str]:
        labels = [MONTHLY, ONE_TIME, KOFI]
        if self.support_has_subscription:
            labels.append(MANAGE)
        return labels + [BACK]

    def activate_support(self) -> None:
        label = self.selected_label()
        if label in (MONTHLY, ONE_TIME):
            self.support_frequency = "monthly" if label == MONTHLY else "onetime"
            self.open_view(SUPPORT_AMOUNTS_VIEW)
            self.reset_selection()
        elif label == KOFI:
            self.open_in_browser(KOFI_URL)
        elif label == MANAGE:
            self.open_manage_subscription()
        else:
            self.return_to("main")

    def support_amounts(self) -> list[tuple]:
        return MONTHLY_AMOUNTS if self.support_frequency == "monthly" else ONE_TIME_AMOUNTS

    def support_amount_labels(self) -> list[str]:
        return [label for label, _url, _cents in self.support_amounts()] + [BACK]

    def activate_support_amount(self) -> None:
        amounts = self.support_amounts()
        if self.selected_index >= len(amounts):
            self.return_to(SUPPORT_VIEW)
            return
        self.support_amount = amounts[self.selected_index]
        self.open_view(SUPPORT_DELIVERY_VIEW)
        self.reset_selection()

    def activate_support_delivery(self) -> None:
        label = self.selected_label()
        if label == OPEN_IN_BROWSER:
            self.open_in_browser(self.support_amount[1])
            self.return_to("main")
        elif label == EMAIL_LINK:
            self.open_keyboard("Email Me a Link", "The payment link is sent to this address.", self.email_support_link)
        else:
            self.return_to(SUPPORT_AMOUNTS_VIEW)

    def email_support_link(self, email: str) -> None:
        email = email.strip()
        if "@" not in email:
            self.flash("Enter a valid email address.", ERROR_SECONDS)
            self.open_keyboard("Email Me a Link", "The payment link is sent to this address.", self.email_support_link, initial=email)
            return
        _label, _url, cents = self.support_amount
        body = {"amount": cents, "frequency": self.support_frequency, "email": email}
        credentials = self.credentials()
        if credentials:
            body.update(raUsername=credentials["user"], raToken=credentials["token"], raUserAgent=RA_USER_AGENT)

        def worker() -> None:
            try:
                post_support("email-invoice", body)
                self.flash("Check your email for the payment link")
            except Exception as exc:
                self.flash(f"Couldn't send the link: {exc}", ERROR_SECONDS)

        threading.Thread(target=worker, daemon=True).start()
        self.return_to("main")

    def open_manage_subscription(self) -> None:
        credentials = self.credentials()
        if credentials is None:
            return

        def worker() -> None:
            try:
                result = post_support(
                    "subscription/portal",
                    {"username": credentials["user"], "token": credentials["token"], "userAgent": RA_USER_AGENT},
                )
                self.open_in_browser(result["url"])
            except Exception:
                self.flash("Could not open subscription management. Please try again later.", ERROR_SECONDS)

        threading.Thread(target=worker, daemon=True).start()

    # Help & about -------------------------------------------------------------------

    def help_labels(self) -> list[str]:
        return ["Documentation", "Contact the developer", "Privacy policy", "Check for updates now", BACK]

    def activate_help(self) -> None:
        label = self.selected_label()
        if label == "Documentation":
            self.open_in_browser(DOCS_URL)
        elif label == "Contact the developer":
            self.open_in_browser(CONTACT_URL)
        elif label == "Privacy policy":
            self.open_in_browser(PRIVACY_URL)
        elif label == "Check for updates now":
            self.start_update_check(force=True)
        else:
            self.return_to("main")

    # Updates ------------------------------------------------------------------------

    def start_update_check(self, force: bool = False) -> None:
        import time

        if not force:
            if self.update_checked_at is not None and time.monotonic() - self.update_checked_at < UPDATE_RECHECK_SECONDS:
                return
            # Set before the setting is read, so with updates off it's read once a minute, not every frame.
            self.update_checked_at = time.monotonic()
            if not setting_enabled(load_config(), UPDATE_CHECK_KEY):
                return

        def worker() -> None:
            try:
                self.update_info = windows_update.check(force=force)
                if force and self.update_info.available:
                    # Opened by the menu's own thread (render), not from here.
                    self.update_found_by_check = True
                elif force:
                    self.flash(f"You're on the latest version ({APP_VERSION})")
            except Exception as exc:
                if force:
                    self.flash(f"Update check failed: {exc}", ERROR_SECONDS)

        threading.Thread(target=worker, daemon=True).start()

    update_found_by_check = False

    def show_update_found_by_check(self) -> None:
        """"Check for updates now" found one: show it there and then, rather
        than only as a new entry back on the main menu."""
        if not self.update_found_by_check:
            return
        self.update_found_by_check = False
        self.open_view(UPDATE_VIEW, "main")
        self.reset_selection()

    def update_label(self) -> str | None:
        info = self.update_info
        return f"Update available: {info.latest_version}" if info is not None and info.available else None

    def update_downloading(self) -> bool:
        return self.update_download_thread is not None and self.update_download_thread.is_alive()

    def start_update_download(self) -> None:
        """In the background, so the menu keeps drawing while ~20 MB downloads."""
        if self.update_downloading():
            return
        def worker() -> None:
            try:
                # Fresh, so a menu left open never installs an offer that's stale.
                info = windows_update.check()
                if not info.available:
                    self.flash("Already up to date")
                    return
                windows_update.download_and_launch_installer(info.asset_url, checksum_url=info.checksum_url)
            except Exception as exc:
                self.flash(f"Update failed: {exc}", ERROR_SECONDS)
                return
            # The installer replaces these files, so get out of its way.
            self.running = False

        self.flash("Downloading update...", 600)
        self.update_download_thread = threading.Thread(target=worker, daemon=True)
        self.update_download_thread.start()

    def update_labels(self) -> list[str]:
        if self.update_downloading():
            return []
        return ["Download and install", "Release notes", "Later"]

    def activate_update(self) -> None:
        label = self.selected_label()
        if label == "Release notes" and self.update_info.release_url:
            self.open_in_browser(self.update_info.release_url)
        elif label == "Download and install":
            self.start_update_download()
        else:
            self.return_to("main")
