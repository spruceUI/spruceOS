"""Settings > Tasks > Download cheats.

Downloads libretro's cheats.zip once (the set RetroArch's own "Update Cheats" uses), then
matches each game by title to a cheat file, locally, and writes the match as
RetroArch/.retroarch/cheats/<system>/<game>.cht so the in-game menu's Cheats list finds it.
Games that already have a cheat file are left alone. RetroArch cores only: standalone emulators
do not read these files.
"""

import os
import re
import time
import zipfile
from email.utils import parsedate_to_datetime
from urllib.request import Request, urlopen

from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from menus.language.language import Language
from utils.boxart.box_art_scraper import BoxArtScraper
from utils.idle_shutdown import pauses_idle_shutdown
from utils.logger import PyUiLogger

CHEATS_URL = "https://buildbot.libretro.com/assets/frontend/cheats.zip"
CHEATS_DIR = "/mnt/SDCARD/RetroArch/.retroarch/cheats"
ZIP_PATH = "/mnt/SDCARD/Saves/spruce/cheats.zip"
TIMEOUT = 30

# rumble patches, not cheats
NOT_CHEATS = re.compile(r"\(Rumbles?\)", re.IGNORECASE)
# pre-release builds: their addresses rarely fit the retail game, so used only when nothing else matches
PRE_RELEASE = re.compile(r"\((Beta|Proto|Prototype|Sample|Demo|Kiosk)\b[^)]*\)", re.IGNORECASE)

_TAGS = re.compile(r"\s*[\(\[][^)\]]*[\)\]]")
_ROMAN = {"ii": "2", "iii": "3", "iv": "4", "v": "5", "vi": "6", "vii": "7", "viii": "8", "ix": "9", "x": "10"}
# dropped from titles: articles move ("Castle, The"), and libretro writes "&" as "_"
_IGNORED = {"the", "a", "an", "and"}

PREFERRED_REGIONS = {
    "us": ["usa", "world", "europe"],
    "eu": ["europe", "world", "usa"],
    "jp": ["japan", "world", "usa"],
    "wor": ["world", "usa", "europe"],
}


def title_key(name: str) -> str:
    """A title with tags, case, punctuation and the words above ignored. Cheats only fit the
    game they were made for, so a match must have the same title: no fuzzy matching."""
    words = re.findall(r"[a-z0-9]+", _TAGS.sub("", name).lower())
    # joined without spaces: "Solar Striker" / "SolarStriker", "Ping Pong" / "Pingpong"
    return "".join(_ROMAN.get(w, w) for w in words if w not in _IGNORED)


def _region_rank(name: str, wanted: list) -> int:
    tags = " ".join(_TAGS.findall(name)).lower()
    for i, region in enumerate(wanted):
        if region in tags:
            return i
    return len(wanted)


def match_cheat(rom_name: str, names: list, spruce_region: str):
    """The cheat file (without .cht) for a ROM, or None. names: the system's cheat files."""
    key = title_key(rom_name)
    if not key:
        return None
    same = [n for n in names if title_key(n) == key]
    if not same and " - " not in _TAGS.sub("", rom_name):
        # libretro's title may add a subtitle ("Kwirk - He's A-maze-ing!"); only if it is one game
        same = [n for n in names if title_key(_TAGS.sub("", n).split(" - ")[0]) == key]
        if len({title_key(n) for n in same}) != 1:
            return None
    if not same:
        return None
    order = _region_order(rom_name, spruce_region)
    return min(same, key=lambda n: (bool(PRE_RELEASE.search(n)), _region_rank(n, order), len(n)))


def _region_order(rom_name: str, spruce_region) -> list:
    """Regions named in the ROM's own tags first, then spruce's preferred region."""
    keys = []
    for tag in re.findall(r"\(([^()]*)\)", rom_name):
        for word in tag.split(","):
            k = {"usa": "us", "europe": "eu", "japan": "jp", "world": "wor"}.get(word.strip().lower())
            if k and k not in keys:
                keys.append(k)
    v = spruce_region.upper() if isinstance(spruce_region, str) else ""
    keys.append("eu" if "EUR" in v else "jp" if "JAP" in v or v in ("JP", "JPN") else "wor" if "WORLD" in v else "us")
    order = []
    for k in keys:
        for region in PREFERRED_REGIONS[k]:
            if region not in order:
                order.append(region)
    return order


# libretro's cheat folders where they differ from its thumbnail folders
CHEAT_FOLDERS = {
    "EIGHTHUNDRED": "Atari - 8-bit Family",
    "NDSI": "Nintendo - Nintendo DS",
    "ZXS": "Sinclair - ZX Spectrum +3",
}


class CheatDownloader:
    def __init__(self):
        self.scraper = BoxArtScraper()
        self.cancelled = False

    def _message(self, text: str, duration_ms: int = 0):
        PyUiLogger.get_logger().info(f"CheatDownloader: {text}")
        Display.display_message(text, duration_ms)

    def _cancel_pressed(self) -> bool:
        if not self.cancelled:
            pressed = Controller.controller_interface.get_input(1)
            if Device.get_device().check_for_button_remap(pressed) == ControllerInput.B:
                self.cancelled = True
        return self.cancelled

    def _download(self) -> bool:
        """Fetch cheats.zip unless the cached copy is current. True when a zip is there to use."""
        have = os.path.exists(ZIP_PATH)
        if not Device.get_device().is_wifi_enabled():
            return have
        request = Request(CHEATS_URL)
        if have:
            request.add_header("If-Modified-Since",
                               time.strftime("%a, %d %b %Y %H:%M:%S GMT", time.gmtime(os.path.getmtime(ZIP_PATH))))
        tmp = ZIP_PATH + ".tmp"
        try:
            with urlopen(request, timeout=TIMEOUT) as response:
                total = int(response.headers.get("Content-Length") or 0)
                modified = response.headers.get("Last-Modified")
                os.makedirs(os.path.dirname(ZIP_PATH), exist_ok=True)
                done, shown = 0, -1
                with open(tmp, "wb") as out:
                    while True:
                        if self._cancel_pressed():
                            break
                        chunk = response.read(256 * 1024)
                        if not chunk:
                            break
                        out.write(chunk)
                        done += len(chunk)
                        mb = done // (1024 * 1024)
                        if mb != shown:
                            shown = mb
                            self._message(Language.label("cheatsDownloading", "Downloading cheats... {done} / {total} MB")
                                          .replace("{done}", str(mb)).replace("{total}", str(total // (1024 * 1024) or "?")))
            if self.cancelled or (total and done != total):
                os.remove(tmp)
                return have and not self.cancelled
            os.replace(tmp, ZIP_PATH)
            if modified:
                stamp = parsedate_to_datetime(modified).timestamp()
                os.utime(ZIP_PATH, (stamp, stamp))
            return True
        except Exception as e:
            # 304 Not Modified arrives as an HTTPError: the cached zip is current
            if getattr(e, "code", None) != 304:
                PyUiLogger.get_logger().warning(f"CheatDownloader: download failed: {e}")
            if os.path.exists(tmp):
                os.remove(tmp)
            return have

    @staticmethod
    def _has_cheats(folder: str, rom_name: str) -> bool:
        """A cheat file the user may have made or edited: never overwritten."""
        return (os.path.exists(os.path.join(CHEATS_DIR, folder, rom_name + ".cht"))
                or os.path.exists(os.path.join(CHEATS_DIR, rom_name + ".cht")))

    @staticmethod
    def _roms(game_system) -> list:
        extensions = tuple(e.lower() for e in game_system.game_system_config.get_extlist())
        images = Device.get_device().get_game_images_folder_name()
        roms = []
        for folder in game_system.folder_paths:
            for root, dirs, files in os.walk(folder):
                dirs[:] = [d for d in dirs if not d.startswith(images) and not d.startswith(".")]
                roms.extend(f for f in files if f.lower().endswith(extensions) and not f.startswith("."))
        return roms

    def _cheat_folder(self, system_name: str):
        return CHEAT_FOLDERS.get(system_name) or self.scraper.get_ra_alias(system_name)

    @pauses_idle_shutdown
    def run(self):
        have_zip = self._download()
        if self.cancelled:
            self._message(Language.label("cheatsStopped", "Stopped."), 2000)
            return
        if not have_zip:
            self._message(Language.label("cheatsNoDownload", "Could not download the cheat list. Connect to Wi-Fi and try again."), 3000)
            return

        self._message(Language.label("cheatsMatching", "Matching cheats to your games..."))
        added = already = 0
        try:
            archive = zipfile.ZipFile(ZIP_PATH)
        except (OSError, zipfile.BadZipFile) as e:
            PyUiLogger.get_logger().warning(f"CheatDownloader: bad zip: {e}")
            os.remove(ZIP_PATH)
            self._message(Language.label("cheatsNoDownload", "Could not download the cheat list. Connect to Wi-Fi and try again."), 3000)
            return

        with archive:
            by_folder = {}
            for name in archive.namelist():
                folder, _, file = name.rpartition("/")
                if file.lower().endswith(".cht"):
                    by_folder.setdefault(folder, []).append(file)

            region = Device.get_device().get_system_config().get_preferred_region()
            systems = Device.get_device().get_game_system_utils().get_active_systems()
            for game_system in systems:
                if self.cancelled:
                    break
                folder = self._cheat_folder(game_system.system_name)
                files = by_folder.get(folder) if folder else None
                if not files:
                    continue
                names = [f[:-4] for f in files if not NOT_CHEATS.search(f)]
                for rom in self._roms(game_system):
                    if self._cancel_pressed():
                        break
                    rom_name = os.path.splitext(rom)[0]
                    if self._has_cheats(folder, rom_name):
                        already += 1
                        continue
                    match = match_cheat(rom_name, names, region)
                    if not match:
                        continue
                    target_dir = os.path.join(CHEATS_DIR, folder)
                    os.makedirs(target_dir, exist_ok=True)
                    target = os.path.join(target_dir, rom_name + ".cht")
                    tmp = target + ".tmp"
                    with open(tmp, "wb") as out:
                        out.write(archive.read(folder + "/" + match + ".cht"))
                    os.replace(tmp, target)
                    added += 1
                    self._message(Language.label("cheatsProgress", "{system}: cheats added for {added} games")
                                  .replace("{system}", game_system.display_name).replace("{added}", str(added)))

        if self.cancelled:
            summary = Language.label("cheatsStoppedSummary", "Stopped. Cheats added for {added} games.")
        else:
            summary = Language.label("cheatsSummary", "Cheats added for {added} games. {already} already had cheats.")
        self._message(summary.replace("{added}", str(added)).replace("{already}", str(already)), 4000)
