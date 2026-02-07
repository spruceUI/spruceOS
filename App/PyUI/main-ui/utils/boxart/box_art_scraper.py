from collections.abc import Set
from concurrent.futures import ThreadPoolExecutor, as_completed
import os
from pathlib import Path
import subprocess
import re
import time
import urllib.request
from typing import List, Optional
import xml.etree.ElementTree as ET
import glob

from devices.device import Device
from display.display import Display
from games.utils.box_art_resizer import BoxArtResizer
from utils.cached_exists import CachedExists
from utils.logger import PyUiLogger
import re
from typing import Optional

class BoxArtScraper:
    """
    Box art scraper with fuzzy matching algorithm.

    Improvements from Rust implementation:
    - Levenshtein edit distance for better fuzzy matching
    - Enhanced token matching (exact, substring with min length, fuzzy)
    - Expanded abbreviation support (13 entries)
    - Bracket and parenthesis removal in normalization
    - Improved weighted similarity algorithm with better penalties
    - Exact match fast path for performance
    - Higher threshold (0.4) to reduce false matches
    - Roman numeral conversion includes "1" → "i"
    """

    # Abbreviation mapping (expanded from Rust implementation)
    ABBREVIATIONS = {
        "ff": "final fantasy",
        "zelda": "legend of zelda",
        "mario": "super mario",
        "smb": "super mario bros",
        "smw": "super mario world",
        "sf": "street fighter",
        "mk": "mortal kombat",
        "dkc": "donkey kong country",
        "cv": "castlevania",
        "mm": "mega man",
        "dr": "doctor",
        "st": "saint",
        "mr": "mister",
    }

    # Numbers → roman numerals (expanded to include 1)
    NUM_TO_ROMAN = {
        "1": "i", "2": "ii", "3": "iii", "4": "iv", "5": "v",
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
        self._arcade_xml_cache = None  # Single global dict: rom_name -> display_name for all arcade systems
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
            "CPS1": "FBNeo - Arcade Games",
            "CPS2": "FBNeo - Arcade Games",
            "CPS3": "FBNeo - Arcade Games",
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

    def _find_game_list_file(self, sys_name: str) -> Optional[str]:
        """
        Find the game list file for a system.
        If the system's file doesn't exist, look for another system with the same LibRetro alias.
        """
        # First try the direct file
        image_list_file = os.path.join(self.db_dir, f"{sys_name}_games.txt")
        if os.path.exists(image_list_file):
            return image_list_file

        # Explicit fallback mappings for systems that should share lists
        fallback_mapping = {
            "CPS1": "ARCADE",         # CPS1 uses ARCADE list (shared MAME repo)
            "CPS2": "ARCADE",         # CPS2 uses ARCADE list (shared MAME repo)
            "CPS3": "ARCADE",         # CPS3 uses ARCADE list (shared MAME repo)
            "MSU1": "SFC",            # MSU1 uses SFC list (shared SNES repo)
            "EIGHTHUNDRED": "ATARI",  # Atari 800 uses main Atari list
        }

        if sys_name in fallback_mapping:
            fallback_sys = fallback_mapping[sys_name]
            fallback_file = os.path.join(self.db_dir, f"{fallback_sys}_games.txt")
            if os.path.exists(fallback_file):
                PyUiLogger.get_logger().info(f"BoxartScraper: Using {fallback_sys}_games.txt for {sys_name}")
                return fallback_file

        return None

    def _is_arcade_system(self, sys_name: str) -> bool:
        """Check if system is an arcade-type system that uses XML for name mapping."""
        arcade_systems = {"ARCADE", "CPS1", "CPS2", "CPS3", "FBNEO", "MAME2003PLUS", "NEOGEO"}
        return sys_name.upper() in arcade_systems

    def _parse_arcade_xml(self) -> dict:
        """
        Parse central MAME XML to get ROM name -> Display name mapping.
        Loads once and caches for all arcade systems.
        Returns empty dict if XML not found or parsing fails.
        """
        # Check if already loaded
        if self._arcade_xml_cache is not None:
            return self._arcade_xml_cache

        # Path to central MAME XML
        xml_path = os.path.join(self.db_dir, "mame_names.xml")

        if not os.path.exists(xml_path):
            PyUiLogger.get_logger().warning(f"BoxartScraper: MAME XML not found at {xml_path}, falling back to ROM filename matching")
            self._arcade_xml_cache = {}
            return {}

        # Parse XML
        try:
            tree = ET.parse(xml_path)
            root = tree.getroot()

            mapping = {}
            for game in root.findall('game'):
                path_elem = game.find('path')
                name_elem = game.find('name')

                if path_elem is not None and name_elem is not None:
                    path_text = path_elem.text
                    name_text = name_elem.text

                    if path_text and name_text:
                        # Strip ./ prefix and .zip extension
                        rom_name = path_text.replace('./', '').replace('.zip', '')
                        mapping[rom_name] = name_text

            PyUiLogger.get_logger().info(f"BoxartScraper: Loaded {len(mapping)} MAME ROM mappings from central XML")
            self._arcade_xml_cache = mapping
            return mapping

        except Exception as e:
            PyUiLogger.get_logger().warning(f"BoxartScraper: Failed to parse MAME XML: {e}")
            self._arcade_xml_cache = {}
            return {}

    def find_image_name(self, sys_name: str, rom_file_name: str) -> Optional[str]:
        """Match ROM to image name based on db/<system>_games.txt."""
        image_list_file = self._find_game_list_file(sys_name)
        if not image_list_file:
            PyUiLogger.get_logger().warning(f"BoxartScraper: Image list file not found for {sys_name}.")
            return None

        rom_without_ext = os.path.splitext(rom_file_name)[0]

        # For arcade systems, use central MAME XML to get display name
        # If not found, skip this ROM entirely (don't attempt fallback matching)
        search_name = rom_without_ext
        if self._is_arcade_system(sys_name):
            xml_mapping = self._parse_arcade_xml()
            if rom_without_ext in xml_mapping:
                search_name = xml_mapping[rom_without_ext]
                PyUiLogger.get_logger().debug(f"BoxartScraper: MAME lookup: {rom_without_ext} -> {search_name}")
            else:
                PyUiLogger.get_logger().debug(f"BoxartScraper: MAME lookup: {rom_without_ext} not found in database, skipping")
                return None  # Skip ROMs not in MAME database

        with open(image_list_file, "r", encoding="utf-8", errors="ignore") as f:
            image_list = f.read().splitlines()

        return self.find_image_from_list(sys_name, search_name, image_list)

    def get_image_list_for_system(self, sys_name: str) -> List[str]:
        """Match ROM to image name based on db/<system>_games.txt."""
        image_list_file = self._find_game_list_file(sys_name)
        if not image_list_file:
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

    @staticmethod
    def edit_distance(a: str, b: str) -> int:
        """
        Calculate Levenshtein edit distance between two strings.
        Imported from Rust implementation for better fuzzy matching.
        """
        a_len = len(a)
        b_len = len(b)

        # Initialize previous row
        prev = list(range(b_len + 1))
        curr = [0] * (b_len + 1)

        for i in range(1, a_len + 1):
            curr[0] = i
            for j in range(1, b_len + 1):
                cost = 0 if a[i - 1] == b[j - 1] else 1
                curr[j] = min(
                    prev[j] + 1,      # deletion
                    curr[j - 1] + 1,  # insertion
                    prev[j - 1] + cost  # substitution
                )
            prev, curr = curr, prev

        return prev[b_len]

    @staticmethod
    def tokens_match(a: str, b: str) -> bool:
        """
        Check if two tokens match using exact, substring, or fuzzy matching.
        Optimized to use Levenshtein sparingly for performance on low-power devices.
        """
        # Exact match (fastest)
        if a == b:
            return True

        # Substring match (very fast, only if shorter token is >= 3 chars)
        if a in b or b in a:
            shorter = min(len(a), len(b))
            if shorter >= 3:
                return True

        # Levenshtein fuzzy match - ONLY for short-medium tokens (4-8 chars)
        # where typos are most common, and only if lengths are similar
        min_len = min(len(a), len(b))
        max_len = max(len(a), len(b))
        if 4 <= min_len <= 8 and max_len - min_len <= 2:
            max_dist = 1  # Only allow 1 character difference for speed
            if BoxArtScraper.edit_distance(a, b) <= max_dist:
                return True

        return False

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

    def normalize_name(self, s: str) -> str:
        """
        Remove all (...) and [...] and normalize spaces/symbols.
        Renamed from strip_parentheses and expanded to match Rust implementation.
        """
        # Remove parentheses and brackets
        s = re.sub(r"\([^)]*\)", "", s)
        s = re.sub(r"\[[^\]]*\]", "", s)
        # Normalize spaces, dashes, underscores, commas
        s = re.sub(r"[\s\-_,]+", " ", s)
        return s.strip()

    def strip_parentheses(self, s: str) -> str:
        """Alias for normalize_name for backward compatibility"""
        return self.normalize_name(s)

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
        """
        Calculate weighted similarity between ROM tokens (target) and candidate tokens.
        Improved algorithm from Rust implementation with better matching and penalties.
        """
        if not target_tokens or not candidate_tokens:
            return 0.0

        matched_target = set()

        # Use improved token matching logic
        for t in target_tokens:
            for c in candidate_tokens:
                if self.tokens_match(t, c):
                    matched_target.add(t)
                    break

        target_len = len(target_tokens)
        candidate_len = len(candidate_tokens)

        # Base score: fraction of ROM tokens that matched
        target_coverage = len(matched_target) / target_len

        # Penalty for missing ROM tokens (important - these are what the user expects)
        missing_tokens = target_tokens - matched_target
        missing_penalty = sum(0.0 if t == "i" else 0.25 for t in missing_tokens)

        # Small penalty for extra candidate tokens (less important)
        extra_candidate = max(candidate_len - target_len, 0)
        extra_penalty = extra_candidate * 0.05

        return max(target_coverage - missing_penalty - extra_penalty, 0.0)    
    
    def find_image_from_list(
        self,
        sys_name: str,
        rom_without_ext: str,
        image_list: List[str],
    ) -> Optional[str]:
        """
        Find the best matching image from the cached list.
        Improved algorithm from Rust implementation with exact match fast path.
        """
        # Precompute token sets for this system if not already cached
        if sys_name not in self._cache:
            self._cache[sys_name] = [
                (name, self.tokenize(self.normalize_name(name.replace(".png", ""))))
                for name in image_list
            ]

        normalized_rom = self.normalize_name(rom_without_ext)
        rom_lower = normalized_rom.lower()

        # Fast path: exact match after normalization
        for name, _ in self._cache[sys_name]:
            normalized_candidate = self.normalize_name(name.replace(".png", "")).lower()
            if rom_lower == normalized_candidate:
                return name

        # Fuzzy matching - check same starting letter first for speed
        target_tokens = self.tokenize(normalized_rom)

        # Get first letter of ROM (after normalization)
        rom_first_letter = rom_lower[0] if rom_lower else ""

        # Separate candidates by starting letter
        same_letter_candidates = []
        other_candidates = []

        for name, candidate_tokens in self._cache[sys_name]:
            candidate_lower = name.lower()
            if candidate_lower and candidate_lower[0] == rom_first_letter:
                same_letter_candidates.append((name, candidate_tokens))
            else:
                other_candidates.append((name, candidate_tokens))

        # Check same-letter candidates first
        best_score = 0.0
        best_candidates = []

        for name, candidate_tokens in same_letter_candidates:
            score = self.weighted_similarity(target_tokens, candidate_tokens)
            # Use small epsilon for floating point comparison
            if score > best_score + 0.001:
                best_score = score
                best_candidates = [name]
            elif abs(score - best_score) <= 0.001:
                best_candidates.append(name)

            # Early exit: if we found an excellent match (85%+), stop searching
            if best_score >= 0.85:
                break

        # If no good match in same-letter section, bail out (don't check other letters)
        # Raised threshold from 0.3 to 0.4 (matches Rust implementation)
        if not best_candidates or best_score < 0.4:
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
    def process_rom(self, sys_name, ra_name, sys_imgs_dir, relative_path, file):

        # Create subfolder structure inside Imgs to mirror ROM folder structure
        target_img_dir = os.path.join(sys_imgs_dir, relative_path)
        if not os.path.exists(target_img_dir):
            os.makedirs(target_img_dir, exist_ok=True)

        rom_name = os.path.splitext(file)[0]
        image_path = os.path.join(target_img_dir, f"{rom_name}.png")

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

        # Central Imgs folder at system level
        sys_imgs_dir = os.path.join(sys_path, "Imgs")

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

            # Calculate relative path from system root to preserve folder structure
            relative_path = os.path.relpath(root, sys_path)
            if relative_path == ".":
                relative_path = ""

            for file in files:
                if not any(file.lower().endswith(ext.lower()) for ext in extensions):
                    continue

                rom_name = os.path.splitext(file)[0]

                # Check if image already exists in mirrored Imgs subfolder
                target_img_dir = os.path.join(sys_imgs_dir, relative_path)
                if os.path.exists(target_img_dir) and any(f.startswith(rom_name + ".") for f in os.listdir(target_img_dir)):
                    continue

                tasks.append((sys_name, ra_name, sys_imgs_dir, relative_path, file))
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
