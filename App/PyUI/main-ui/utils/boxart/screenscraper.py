"""Box art from ScreenScraper for a signed-in user (api2, screenscraper.fr/webapi2.php).

ScreenScraper wants a checksum and the file size with every lookup, so ROMs are matched by CRC32
(read from the zip index when the zip holds one file, otherwise computed) rather than by name.
spruce's developer credentials come from ss.bin, which the release workflows write from GitHub
secrets; without it, or without a signed-in user, callers use libretro only.
The user's login is kept in plain text, as Skyscraper and Scrappy keep it.
"""

import base64
import json
import os
import ssl
import threading
import time
import zipfile
import zlib
from contextlib import contextmanager
from typing import Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import urlopen

from utils.boxart import ss_regions
from utils.logger import PyUiLogger

API = "https://api.screenscraper.fr/api2/"
SOFTNAME = "spruceOS"
DEV_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ss.bin")
# Not protection (the key ships beside it): only keeps the developer login out of plain-text
# searches of release archives. The workflows encode it the same way.
DEV_KEY = b"spruceOS box art"
USER_FILE = "/mnt/SDCARD/Saves/spruce/screenscraper.json"
HASH_LIMIT = 64 * 1024 * 1024
TIMEOUT = 20
BUSY_RETRIES = 5

# Why a run stops using ScreenScraper; the rest of the run uses libretro
LOGIN = "login"        # user name/password (or our developer account) rejected
QUOTA = "quota"        # today's request allowance is used up
CLOSED = "closed"      # API closed, for everyone or for this kind of account
NETWORK = "network"    # no connection to ScreenScraper
CLOCK = "clock"        # TLS certificate rejected: almost always a wrong system clock


class ScreenScraperError(Exception):
    def __init__(self, kind: str, detail: str = ""):
        super().__init__(f"{kind}: {detail}" if detail else kind)
        self.kind = kind


def _load(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _load_dev(path: str) -> dict:
    try:
        with open(path, "rb") as f:
            raw = base64.b64decode(f.read())
        data = json.loads(bytes(b ^ DEV_KEY[i % len(DEV_KEY)] for i, b in enumerate(raw)))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def rom_hash(path: str):
    """(CRC32 as 8 hex digits, size, file name) for a ROM, or None when it cannot be hashed."""
    try:
        if path.lower().endswith(".zip") and zipfile.is_zipfile(path):
            with zipfile.ZipFile(path) as z:
                files = [i for i in z.infolist() if not i.is_dir()]
            if len(files) == 1:
                member = files[0]
                return f"{member.CRC:08X}", member.file_size, os.path.basename(member.filename)
        size = os.path.getsize(path)
        if size > HASH_LIMIT:
            return None
        crc = 0
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                crc = zlib.crc32(chunk, crc)
        return f"{crc & 0xFFFFFFFF:08X}", size, os.path.basename(path)
    except (OSError, zipfile.BadZipFile):
        return None


class ScreenScraper:
    def __init__(self):
        dev = _load_dev(DEV_FILE)
        user = _load(USER_FILE)
        self.devid = str(dev.get("devid", ""))
        self.devpassword = str(dev.get("devpassword", ""))
        self.username = str(user.get("username", ""))
        self.password = str(user.get("password", ""))
        self.stopped = None  # set to a reason when this run gave up on ScreenScraper
        self.threads = 1
        self._slots = threading.BoundedSemaphore(1)
        self._stop_lock = threading.Lock()

    def has_dev_credentials(self) -> bool:
        return bool(self.devid and self.devpassword)

    def signed_in(self) -> bool:
        return bool(self.username and self.password)

    def ready(self) -> bool:
        return self.has_dev_credentials() and self.signed_in() and self.stopped is None

    @staticmethod
    def save_login(username: str, password: str):
        os.makedirs(os.path.dirname(USER_FILE), exist_ok=True)
        tmp = USER_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"username": username, "password": password}, f)
        os.replace(tmp, USER_FILE)

    @staticmethod
    def sign_out():
        try:
            os.remove(USER_FILE)
        except FileNotFoundError:
            pass

    def stop(self, kind: str):
        with self._stop_lock:
            if self.stopped is None:
                self.stopped = kind
                PyUiLogger.get_logger().warning(f"ScreenScraper: stopped for this run ({kind})")

    def _params(self, **extra) -> str:
        params = {
            "devid": self.devid,
            "devpassword": self.devpassword,
            "softname": SOFTNAME,
            "output": "json",
            "ssid": self.username,
            "sspassword": self.password,
        }
        params.update(extra)
        return urlencode(params)

    def _get(self, endpoint: str, **params) -> Optional[dict]:
        """The decoded answer, or None when ScreenScraper does not know the game."""
        url = API + endpoint + "?" + self._params(**params)
        for attempt in range(BUSY_RETRIES + 1):
            try:
                with urlopen(url, timeout=TIMEOUT) as response:
                    body = response.read()
                return json.loads(body.decode("utf-8", errors="replace"))
            except HTTPError as e:
                if e.code == 404:
                    return None
                if e.code == 429:
                    # every thread the account allows is busy: wait, then give this game up
                    if attempt < BUSY_RETRIES:
                        time.sleep(2 + attempt)
                        continue
                    return None
                if e.code == 403:
                    raise ScreenScraperError(LOGIN, f"HTTP {e.code}")
                if e.code in (430, 431):
                    raise ScreenScraperError(QUOTA, f"HTTP {e.code}")
                if e.code in (401, 423, 426):
                    raise ScreenScraperError(CLOSED, f"HTTP {e.code}")
                PyUiLogger.get_logger().info(f"ScreenScraper: {endpoint} HTTP {e.code}")
                return None
            except URLError as e:
                if isinstance(e.reason, ssl.SSLCertVerificationError):
                    raise ScreenScraperError(CLOCK, str(e.reason))
                raise ScreenScraperError(NETWORK, str(e.reason))
            except (OSError, ValueError) as e:
                raise ScreenScraperError(NETWORK, str(e))
        return None

    def account(self) -> dict:
        """ScreenScraper's ssuser record for the signed-in user; raises ScreenScraperError."""
        data = self._get("ssuserInfos.php")
        user = (data or {}).get("response", {}).get("ssuser")
        if not isinstance(user, dict):
            raise ScreenScraperError(LOGIN, "no user record")
        return user

    def start(self) -> dict:
        """Check the login and use as many threads as the account allows."""
        user = self.account()
        try:
            self.threads = max(1, int(user.get("maxthreads", 1)))
        except (TypeError, ValueError):
            self.threads = 1
        self._slots = threading.BoundedSemaphore(self.threads)
        return user

    @contextmanager
    def slot(self):
        with self._slots:
            yield

    def box_art_url(self, system_id: int, rom_path: str, rom_name: str, spruce_region,
                    max_width: int, max_height: int, cancelled=None) -> Optional[str]:
        """URL of the front box for a ROM, or None. Raises ScreenScraperError to stop the run.

        cancelled: checked once a thread is free, so a stopped run skips lookups still queued.
        """
        found = rom_hash(rom_path)
        if not found:
            return None
        crc, size, file_name = found
        with self.slot():
            if cancelled is not None and cancelled():
                return None
            data = self._get("jeuInfos.php", romtype="rom", systemeid=system_id,
                             romnom=file_name, romtaille=size, crc=crc)
        game = (data or {}).get("response", {}).get("jeu")
        if not isinstance(game, dict):
            return None
        boxes = [m for m in game.get("medias", []) if isinstance(m, dict)
                 and m.get("type") == "box-2D" and m.get("url")]
        if not boxes:
            return None
        order = ss_regions.priorities(rom_name, spruce_region)
        rank = {key: i for i, key in enumerate(order)}
        boxes.sort(key=lambda m: rank.get(m.get("region", ""), len(rank)))
        return boxes[0]["url"] + "&" + urlencode(
            {"maxwidth": max_width, "maxheight": max_height, "outputformat": "png"})
