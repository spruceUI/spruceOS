from collections.abc import Set
from concurrent.futures import ThreadPoolExecutor, as_completed
import os
from pathlib import Path
import subprocess
import re
import time
import urllib.request
from typing import List, Optional

from devices.device import Device
from display.display import Display
from games.utils.box_art_resizer import BoxArtResizer
from utils.cached_exists import CachedExists
from utils.logger import PyUiLogger
import re
from typing import Optional

class BoxArtScraper:
    # optional abbreviation mapping
    ABBREVIATIONS = {
        "ff": "final fantasy",
        "zelda": "legend of zelda",
        "mario": "super mario",
        # add more as needed
    }

    # numbers → roman numerals
    NUM_TO_ROMAN = {
        "2": "ii", "3": "iii", "4": "iv", "5": "v",
        "6": "vi", "7": "vii", "8": "viii", "9": "ix", "10": "x"
    }

    STOPWORDS = {"and", "the", "of", "in", "is", "a", "an"}
    """
    Python version of the box art scraper script, converted into a class.
    Matches original shell behavior but without watchdog logic.
    """

    def __init__(self):
        self.base_dir = "/mnt/SDCARD"
        self.roms_dir = Device.get_device().get_roms_dir()
        script_dir = Path(__file__).resolve().parent.parent.parent.parent
        self.db_dir = os.path.join(script_dir,"boxartdb")
        PyUiLogger.get_logger().info(f"BoxArtScraper: Using boxart db directory at {self.db_dir}")
        self.game_system_utils = Device.get_device().get_game_system_utils()
        self.preferred_region = Device.get_device().get_system_config().get_preferred_region()
        self._cache = {}  # sys_name -> list of (filename, token_set)
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
        game_system = self.game_system_utils.get_game_system_by_name(sys_name)
        if(game_system is None):
            return []
        else:
            return game_system.game_system_config.get_extlist()

    def find_image_name(self, sys_name: str, rom_file_name: str) -> Optional[str]:
        """Match ROM to image name based on db/<system>_games.txt."""
        image_list_file = os.path.join(self.db_dir, f"{sys_name}_games.txt")
        if not os.path.exists(image_list_file):
            PyUiLogger.get_logger().warning(f"BoxartScraper: Image list file not found for {sys_name}.")
            return None

        rom_without_ext = os.path.splitext(rom_file_name)[0]
        with open(image_list_file, "r", encoding="utf-8", errors="ignore") as f:
            image_list = f.read().splitlines()

        return self.find_image_from_list(sys_name, rom_without_ext, image_list)

    def get_image_list_for_system(self, sys_name: str) -> List[str]:
        """Match ROM to image name based on db/<system>_games.txt."""
        image_list_file = os.path.join(self.db_dir, f"{sys_name}_games.txt")
        if not os.path.exists(image_list_file):
            self.log_and_display_message(f"Image list file not found for {sys_name}.")
            time.sleep(2)
            return None

        with open(image_list_file, "r", encoding="utf-8", errors="ignore") as f:
            image_list = f.read().splitlines()

        return image_list
    

    def preprocess_token(self, token: str) -> str:
        token = token.lower()
        if token in self.ABBREVIATIONS:
            return self.ABBREVIATIONS[token]
        if token in self.NUM_TO_ROMAN:
            return self.NUM_TO_ROMAN[token]
        return token

    def split_long_token(self, token: str) -> Set[str]:
        """
        For long concatenated words with no spaces, generate simple split.
        Example: "dragonball" -> {"dragonball", "dragon", "ball"}
        """
        token = token.lower()
        if len(token) < 6 or " " in token:
            return {token}

        # Simple heuristic: split near the middle
        mid = len(token) // 2
        return {token, token[:mid], token[mid:]}

    def strip_parentheses(self, s: str) -> str:
        """Remove all (...) and normalize spaces/symbols"""
        s = re.sub(r"\(.*?\)", "", s)
        s = re.sub(r"[\s\-_,]+", " ", s)
        return s.strip()

    def tokenize(self, s: str) -> Set[str]:
        """Convert string to set of tokens, preprocess abbreviations/numbers, remove stopwords"""
        s = s.replace("[_-]", " ").lower()
        s = re.sub(r"[^\w\s]+", " ", s)  # remove punctuation
        tokens = set()
        for t in s.split():
            if t in self.STOPWORDS:
                continue
            t = self.preprocess_token(t)
            tokens |= self.split_long_token(t)
        return tokens
        
    def weighted_similarity(self, target_tokens: Set[str], candidate_tokens: Set[str]) -> float:
        matched_tokens = set()
        for t in target_tokens:
            for c in candidate_tokens:
                if t in c or c in t:  # substring-aware match
                    matched_tokens.add(t)
                    break

        # missing tokens are target tokens that didn't match any candidate token
        missing_tokens = target_tokens - matched_tokens
        penalty = sum(0 if t in {"1", "i"} else 0.3 for t in missing_tokens)

        # union for score denominator can remain the original union
        score = len(matched_tokens) / len(target_tokens | candidate_tokens)

        return max(score - penalty, 0.0)    
    
    def find_image_from_list(
        self,
        sys_name: str,
        rom_without_ext: str,
        image_list: List[str],
    ) -> Optional[str]:

        # Precompute token sets for this system if not already cached
        if sys_name not in self._cache:
            self._cache[sys_name] = [
                (name, self.tokenize(self.strip_parentheses(name.replace(".png", ""))))
                for name in image_list
            ]

        target_tokens = self.tokenize(self.strip_parentheses(rom_without_ext))
        best_score = 0.0
        best_candidates = []

        for name, candidate_tokens in self._cache[sys_name]:
            score = self.weighted_similarity(target_tokens, candidate_tokens)
            if score > best_score:
                best_score = score
                best_candidates = [name]
            elif score == best_score:
                best_candidates.append(name)

        if not best_candidates or best_score < 0.3:
            return None

        # Preferred region tie-breaker
        if self.preferred_region:
            for candidate in best_candidates:
                matches = re.findall(r"\(([^)]*?)\)", candidate, re.IGNORECASE)
                for match in matches:
                    if self.preferred_region in match.upper():
                        return candidate

        # Shortest filename tie-breaker
        return min(best_candidates, key=len)
    # ==========================================================
    # Main Scraper Logic
    # ==========================================================
    
    # Function to process a single ROM file
    def process_rom(self,sys_name, ra_name, root, file):
                
        if not os.path.exists(os.path.join(root, "Imgs")):
            os.makedirs(os.path.join(root, "Imgs"), exist_ok=True)

        rom_name = os.path.splitext(file)[0]
        image_path = os.path.join(root, "Imgs", f"{rom_name}.png")

        if self.download_boxart(sys_name, rom_name, image_path):
            return image_path
        else:
            return None
        
    def download_boxart(self, sys_name: str, rom_file_name: str, image_path: str) -> bool:
        ra_name = self.get_ra_alias(sys_name)
        if not ra_name:
            self.log_message(f"BoxartScraper: Remote system name not found - skipping {sys_name}.")
            return False

        remote_image_name = self.find_image_name(sys_name, rom_file_name)
        if not remote_image_name:
            self.log_message(f"BoxartScraper: No image found for {rom_file_name} in {sys_name}.")
            return False
        return self.download_remote_image(ra_name, remote_image_name, image_path)

    def download_remote_image_for_system(self, sys_name: str, remote_image_name: str, image_path: str):
        ra_name = self.get_ra_alias(sys_name)
        return self.download_remote_image(ra_name, remote_image_name, image_path)

    def download_remote_image(self, ra_name, remote_image_name, image_path):
        CachedExists.clear()

        boxart_url = f"http://thumbnails.libretro.com/{ra_name}/Named_Boxarts/{remote_image_name}".replace(" ", "%20")
        fallback_url = f"https://raw.githubusercontent.com/libretro-thumbnails/{ra_name.replace(' ', '_')}/master/Named_Boxarts/{remote_image_name}".replace(" ", "%20")

        self.log_message(f"BoxartScraper: Downloading {boxart_url}")
        success = self._download_file(boxart_url, image_path)
        if not success:
            self.log_message(f"BoxartScraper: failed {boxart_url}, trying fallback.")
            if not self._download_file(fallback_url, image_path):
                self.log_message(f"BoxartScraper: failed {fallback_url}.")
        return success

    def download_boxart_batch(
        self,
        sys_name: str,
        roms_and_paths: list[tuple[str, str]],
        max_workers: int = 8,
    ):
        if(not self.check_wifi()):
            return

        """
        Run download_boxart() concurrently for a batch of ROM/image pairs.

        roms_and_paths: list of (rom_file_name, image_path)
        """
        self.log_and_display_message("Scraping box art. Please be patient, especially with large libraries!")
        if not roms_and_paths:
            self.log_and_display_message(f"No roms are missing boxart for {sys_name}.")
            time.sleep(2)
            return

        ra_name = self.get_ra_alias(sys_name)
        if not ra_name:
            self.log_and_display_message(f"Remote system name not found - unable to download box art for {sys_name}.")
            time.sleep(2)
            return

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [
                executor.submit(self.download_boxart, sys_name, rom_file_name, image_path)
                for rom_file_name, image_path in roms_and_paths
            ]

            count = 0

            for future in as_completed(futures):
                count = count +1
                self.log_and_display_message(f"Scraping box art... ({count}/{len(roms_and_paths)})")
                try:
                    future.result()  # triggers exception if any occurred
                except Exception as e:
                    self.log_message(f"BoxartScraper: Error in batch download - {e}")
        
        BoxArtResizer.patch_boxart_list([p for _, p in roms_and_paths])

    def run_scraper_tasks(self, max_workers, tasks):
        downloaded_files = []
        # Run tasks concurrently
        count = 0
        success_count = 0
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [executor.submit(self.process_rom, *t) for t in tasks]

            for future in as_completed(futures):
                count = count +1
                self.log_and_display_message(f"Scraping box art... ({count}/{len(tasks)}). Found {success_count} so far.")
                try:
                    result = future.result()
                    if result: 
                        success_count = success_count +1
                        downloaded_files.append(result)
                except Exception as e:
                    self.log_message(f"BoxartScraper: Error processing a ROM - {e}")

        self.log_and_display_message("Scraping complete!")
        time.sleep(2)
        BoxArtResizer.patch_boxart_list(downloaded_files)


    def get_scrape_tasks_for_system(self, sys_dir: str) -> List[tuple]:
        tasks = []

        sys_path = os.path.join(self.roms_dir, sys_dir)
        sys_name = os.path.basename(sys_path)

        ra_name = self.get_ra_alias(sys_name)
        if not ra_name:
            self.log_message(f"BoxartScraper: Remote system name not found - skipping {sys_name}.")
            return tasks

        extensions = self._get_supported_extensions(sys_name)
        if not extensions:
            self.log_message(f"BoxartScraper: No supported extensions found for {sys_name}.")
            return tasks

        for root, _, files in os.walk(sys_path):
            if "Imgs" in root:
                continue

            for file in files:
                if not any(file.lower().endswith(ext.lower()) for ext in extensions):
                    continue

                rom_name = os.path.splitext(file)[0]
                image_dir = os.path.join(root, "Imgs")

                # Skip if image already exists
                if os.path.exists(image_dir) and any(f.startswith(rom_name + ".") for f in os.listdir(image_dir)):
                    continue

                tasks.append((sys_name, ra_name, root, file))
        return tasks

    def check_wifi(self):
        if not Device.get_device().is_wifi_enabled():
            Display.display_message("Wifi must be connected", 2000)
            return False

        if not self._ping("thumbnails.libretro.com"):
            self.log_and_display_message("Libretro thumbnail service unavailable; trying fallback.")
            if not self._ping("github.com"):
                self.log_and_display_message(
                    "Libretro thumbnail GitHub repo is also currently unavailable. Please try again later."
                )
                time.sleep(3)
                return False
        return True
            
    def scrape_boxart(self, max_workers=8):
        self.log_and_display_message(
            "Scraping box art. Please be patient, especially with large libraries!"
        )

        if(not self.check_wifi()):
            return
        
        tasks = []
        # First, collect all ROM files for all systems
        for sys_dir in [d for d in os.listdir(self.roms_dir) if os.path.isdir(os.path.join(self.roms_dir, d))]:
            tasks.extend(self.get_scrape_tasks_for_system(sys_dir))

        self.run_scraper_tasks(max_workers, tasks)
        


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
