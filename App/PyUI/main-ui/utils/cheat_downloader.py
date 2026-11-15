"""Settings > Tasks > Download cheats.

Downloads libretro's cheats.zip once (the set RetroArch's own "Update Cheats" uses), then
matches each game by name to a cheat file, locally, with the box art scraper's matcher (libretro
names cheats and thumbnails the same way), and writes the match as
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

            systems = Device.get_device().get_game_system_utils().get_active_systems()
            for game_system in systems:
                if self.cancelled:
                    break
                folder = self._cheat_folder(game_system.system_name)
                files = by_folder.get(folder) if folder else None
                if not files:
                    continue
                # the matcher compares thumbnail names; give it the cheat names in that form
                every = [f[:-4] + ".png" for f in files if not NOT_CHEATS.search(f)]
                retail = [c for c in every if not PRE_RELEASE.search(c)]
                for rom in self._roms(game_system):
                    if self._cancel_pressed():
                        break
                    rom_name = os.path.splitext(rom)[0]
                    if self._has_cheats(folder, rom_name):
                        already += 1
                        continue
                    # separate cache keys: the matcher caches its token lists per key
                    match = (self.scraper.find_image_from_list(game_system.system_name + ":retail", rom_name, retail)
                             or self.scraper.find_image_from_list(game_system.system_name + ":all", rom_name, every))
                    if not match:
                        continue
                    target_dir = os.path.join(CHEATS_DIR, folder)
                    os.makedirs(target_dir, exist_ok=True)
                    target = os.path.join(target_dir, rom_name + ".cht")
                    tmp = target + ".tmp"
                    with open(tmp, "wb") as out:
                        out.write(archive.read(folder + "/" + match[:-4] + ".cht"))
                    os.replace(tmp, target)
                    added += 1
                    self._message(Language.label("cheatsProgress", "{system}: cheats added for {added} games")
                                  .replace("{system}", game_system.display_name).replace("{added}", str(added)))

        if self.cancelled:
            summary = Language.label("cheatsStoppedSummary", "Stopped. Cheats added for {added} games.")
        else:
            summary = Language.label("cheatsSummary", "Cheats added for {added} games. {already} already had cheats.")
        self._message(summary.replace("{added}", str(added)).replace("{already}", str(already)), 4000)
