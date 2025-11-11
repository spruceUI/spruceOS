import os
import subprocess
import json
import re
import time
import urllib.request
from typing import Optional

from devices.device import Device
from display.display import Display
from games.utils.box_art_resizer import BoxArtResizer
from utils.logger import PyUiLogger


class BoxArtScraper:
    """
    Python version of the box art scraper script, converted into a class.
    Matches original shell behavior but without watchdog logic.
    """

    def __init__(self):
        self.base_dir = "/mnt/SDCARD"
        self.sprig_dir = os.path.join(self.base_dir, "sprig")
        self.emu_dir = os.path.join(self.base_dir, "Emu")
        self.roms_dir = os.path.join(self.base_dir, "Roms")
        self.db_dir = os.path.join(self.sprig_dir, "db")

    # ==========================================================
    # Helper Methods
    # ==========================================================

    def _ping(self, host: str, count: int = 2, timeout: int = 2) -> bool:
        """Ping a host to check connectivity."""
        result = subprocess.call(
            ["ping", "-c", str(count), "-W", str(timeout), host],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return result == 0

    def log_message(self, msg: str):
        PyUiLogger.get_logger().info(msg)

    def log_and_display_message(self, msg: str):
        self.log_message(msg)
        Display.display_message(msg)

    def is_wifi_connected(self) -> bool:
        """Check network connectivity by pinging Cloudflare."""
        if self._ping("1.1.1.1", count=3, timeout=2):
            self.log_message("Cloudflare ping successful; device is online.")
            return True
        else:
            self.log_and_display_message("Cloudflare ping failed; device is offline. Aborting.")
            return False

    def get_ra_alias(self, system: str) -> str:
        """Return Libretro alias name for system."""
        mapping = {
            "AMIGA": "Commodore - Amiga",
            "ATARI": "Atari - 2600",
            "ATARIST": "Atari - ST",
            "ARCADE": "MAME",
            "CPS1": "MAME",
            "CPS2": "MAME",
            "CPS3": "MAME",
            "ARDUBOY": "Arduboy Inc - Arduboy",
            "CHAI": "ChaiLove",
            "COLECO": "Coleco - ColecoVision",
            "COMMODORE": "Commodore - 64",
            "CPC": "Amstrad - CPC",
            "DC": "Sega - Dreamcast",
            "DOOM": "DOOM",
            "DOS": "DOS",
            "EIGHTHUNDRED": "Atari - 8-bit",
            "FAIRCHILD": "Fairchild - Channel F",
            "FBNEO": "FBNeo - Arcade Games",
            "FC": "Nintendo - Nintendo Entertainment System",
            "FDS": "Nintendo - Family Computer Disk System",
            "FIFTYTWOHUNDRED": "Atari - 5200",
            "GB": "Nintendo - Game Boy",
            "GBA": "Nintendo - Game Boy Advance",
            "GBC": "Nintendo - Game Boy Color",
            "GG": "Sega - Game Gear",
            "GW": "Handheld Electronic Game",
            "INTELLIVISION": "Mattel - Intellivision",
            "LYNX": "Atari - Lynx",
            "MD": "Sega - Mega Drive - Genesis",
            "MS": "Sega - Master System - Mark III",
            "MSU1": "Nintendo - Super Nintendo Entertainment System",
            "MSUMD": "Sega - Mega Drive - Genesis",
            "MSX": "Microsoft - MSX",
            "N64": "Nintendo - Nintendo 64",
            "NDS": "Nintendo - Nintendo DS",
            "NEOCD": "SNK - Neo Geo CD",
            "NEOGEO": "SNK - Neo Geo",
            "NGP": "SNK - Neo Geo Pocket",
            "NGPC": "SNK - Neo Geo Pocket Color",
            "ODYSSEY": "Magnavox - Odyssey2",
            "PCE": "NEC - PC Engine - TurboGrafx 16",
            "PCECD": "NEC - PC Engine CD - TurboGrafx-CD",
            "POKE": "Nintendo - Pokemon Mini",
            "PS": "Sony - PlayStation",
            "PSP": "Sony - PlayStation Portable",
            "QUAKE": "Quake",
            "SATELLAVIEW": "Nintendo - Satellaview",
            "SATURN": "Sega - Saturn",
            "SCUMMVM": "ScummVM",
            "SEGACD": "Sega - Mega-CD - Sega CD",
            "SEGASGONE": "Sega - SG-1000",
            "SEVENTYEIGHTHUNDRED": "Atari - 7800",
            "SFC": "Nintendo - Super Nintendo Entertainment System",
            "SGB": "Nintendo - Game Boy",
            "SGFX": "NEC - PC Engine SuperGrafx",
            "SUFAMI": "Nintendo - Sufami Turbo",
            "SUPERVISION": "Watara - Supervision",
            "THIRTYTWOX": "Sega - 32X",
            "TIC": "TIC-80",
            "VB": "Nintendo - Virtual Boy",
            "VECTREX": "GCE - Vectrex",
            "VIC20": "Commodore - VIC-20",
            "VIDEOPAC": "Philips - Videopac+",
            "WOLF": "Wolfenstein 3D",
            "WS": "Bandai - WonderSwan",
            "WSC": "Bandai - WonderSwan Color",
            "X68000": "Sharp - X68000",
            "ZXS": "Sinclair - ZX Spectrum",
        }
        return mapping.get(system.upper(), "")

    def _get_supported_extensions(self, sys_name: str) -> list[str]:
        """Get extensions from Emu config.json."""
        config_path = os.path.join(self.emu_dir, sys_name, "config.json")
        if not os.path.exists(config_path):
            return []

        try:
            with open(config_path, "r") as f:
                data = json.load(f)
                extlist = data.get("extlist", "")
                return [ext.strip() for ext in extlist.split("|") if ext.strip()]
        except Exception as e:
            self.log_message(f"BoxartScraper: Failed to read extensions for {sys_name}: {e}")
            return []

    def find_image_name(self, sys_name: str, rom_file_name: str) -> Optional[str]:
        """Match ROM to image name based on db/<system>_games.txt."""
        image_list_file = os.path.join(self.db_dir, f"{sys_name}_games.txt")
        if not os.path.exists(image_list_file):
            return None

        rom_without_ext = os.path.splitext(rom_file_name)[0]
        with open(image_list_file, "r", encoding="utf-8", errors="ignore") as f:
            image_list = f.read().splitlines()

        # Try exact match
        exact = f"{rom_without_ext}.png"
        for name in image_list:
            if name.lower() == exact.lower():
                return name

        # Fuzzy match: remove brackets and region info
        search_term = re.sub(r"\[.*?\]|\(.*?\)", "", rom_without_ext).strip()
        matches = [n for n in image_list if n.lower().startswith(search_term.lower())]
        if matches:
            usa_matches = [m for m in matches if "(USA)" in m]
            return usa_matches[0] if usa_matches else matches[0]
        return None

    # ==========================================================
    # Main Scraper Logic
    # ==========================================================

    def scrape_boxart(self):
        self.log_and_display_message(
            "Scraping box art. Please be patient, especially with large libraries!"
        )
        #time.sleep(1)

        if not Device.is_wifi_enabled():
            Display.display_message("Wifi must be connected",2000)

        if not self._ping("thumbnails.libretro.com"):
            self.log_and_display_message("Libretro thumbnail service unavailable; trying fallback.")
            if not self._ping("github.com"):
                self.log_and_display_message(
                    "Libretro thumbnail GitHub repo is also currently unavailable. Please try again later."
                )
                time.sleep(3)
                return

        for sys_dir in [d for d in os.listdir(self.roms_dir) if os.path.isdir(os.path.join(self.roms_dir, d))]:
            sys_path = os.path.join(self.roms_dir, sys_dir)
            sys_name = os.path.basename(sys_path)

            ra_name = self.get_ra_alias(sys_name)
            if not ra_name:
                self.log_message(f"BoxartScraper: Remote system name not found - skipping {sys_name}.")
                continue

            extensions = self._get_supported_extensions(sys_name)
            if not extensions:
                self.log_message(f"BoxartScraper: No supported extensions found for {sys_name}.")
                continue

            first_game = True
            for root, _, files in os.walk(sys_path):
                for file in files:
                    if not any(file.lower().endswith(f".{ext.lower()}") for ext in extensions):
                        continue

                    if not os.path.exists(os.path.join(root, "Imgs")):
                        os.makedirs(os.path.join(root, "Imgs"), exist_ok=True)

                    rom_name = os.path.splitext(file)[0]
                    image_path = os.path.join(root, "Imgs", f"{rom_name}.png")

                    # Skip if any image already exists
                    existing = [
                        f for f in os.listdir(os.path.join(root, "Imgs"))
                        if f.startswith(rom_name + ".")
                    ]
                    if existing:
                        continue

                    if first_game:
                        self.log_and_display_message(f"BoxartScraper: Scraping box art for {sys_name}")

                        for f in files[:5]:  # just print the first 5
                            self.log_message(f"{f.get_name()}, {f.get_download_url()}")
                        first_game = False

                    remote_image_name = self.find_image_name(sys_name, file)
                    if not remote_image_name:
                        continue

                    boxart_url = f"http://thumbnails.libretro.com/{ra_name}/Named_Boxarts/{remote_image_name}".replace(" ", "%20")
                    fallback_url = f"https://raw.githubusercontent.com/libretro-thumbnails/{ra_name.replace(' ', '_')}/master/Named_Boxarts/{remote_image_name}".replace(" ", "%20")

                    self.log_message(f"BoxartScraper: Downloading {boxart_url}")
                    success = self._download_file(boxart_url, image_path)
                    if not success:
                        self.log_message(f"BoxartScraper: failed {boxart_url}, trying fallback.")
                        if not self._download_file(fallback_url, image_path):
                            self.log_message(f"BoxartScraper: failed {fallback_url}.")

        self.log_and_display_message("Scraping complete!")
        time.sleep(2)
        BoxArtResizer.patch_boxart()

    # ==========================================================
    # File Download
    # ==========================================================

    def _download_file(self, url: str, dest_path: str) -> bool:
        """Download file to destination path."""
        try:
            urllib.request.urlretrieve(url, dest_path)
            return True
        except Exception:
            if os.path.exists(dest_path):
                os.remove(dest_path)
            return False
