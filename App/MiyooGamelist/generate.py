#!/usr/bin/env python3
"""
MiyooGamelist Generator — generates miyoogamelist.xml files for ROM systems.
"""

import json
import os
import re
import csv
import time
import shutil
from html import escape as html_escape

from display.display import Display
from controller.controller import Controller
from controller.controller_inputs import ControllerInput

def display_image_and_text(
    image_path: str,
    text: str,
    size: int = 35,
    img_y: int = 25,
    text_y: int = 75,
) -> None:

    Display.clear("")
    Display.render_image_and_text(image_path, text, size, img_y, text_y)
    Display.present()

# ---------------------------------------------------------------------------
# ROM Name Cleaner
# ---------------------------------------------------------------------------

class RomNameCleaner:
    """Cleans ROM filenames into display-friendly names.

    Replicates the exact behaviour of functions.sh clean_name().
    """

    @staticmethod
    def strip_extensions(name: str, extlist: set) -> str:
        """Iteratively strip known extensions from a filename.

        Args:
            name: The filename (e.g. "Game.zip.nes").
            extlist: Set of extensions WITHOUT dot (e.g. {"zip", "nes"}).
        """
        while True:
            old_name = name
            for ext in extlist:
                if name.endswith("." + ext):
                    name = name[: -(len(ext) + 1)]
                    break
            if name == old_name:
                break
        return name

    @staticmethod
    def clean_name(filename: str, extlist: set) -> str:
        """Clean a ROM filename into a display name.

        Steps match functions.sh lines 28-69 exactly:
        1. Strip all matching file extensions (iteratively)
        2. Remove (parenthesised text)
        3. Remove [bracketed text]
        4. Remove leading numbers with dots (e.g. "001.")
        5. Replace underscores with spaces
        6. Strip / collapse whitespace
        7. Move leading articles to the end ("The Game" -> "Game, The")
        8. Replace " - " with ": "
        """
        name = RomNameCleaner.strip_extensions(filename, extlist)
        name = re.sub(r"\([^)]*\)", "", name)
        name = re.sub(r"\[[^\]]*\]", "", name)
        name = re.sub(r"^[0-9]+\.", "", name)
        name = name.replace("_", " ")
        name = " ".join(name.split())

        # A leading article moves to the end of the whole name:
        # "The Legend of Zelda, Ocarina of Time - Master Quest" becomes
        # "Legend of Zelda, Ocarina of Time - Master Quest, The". The rule this
        # replaces went the other way, and only when the article ended the
        # string - so "Legend of Zelda, The.nes" became "The Legend of Zelda"
        # while "Legend of Zelda, The - Ocarina of Time.nes" kept its comma,
        # filing one series under two letters.
        m = re.match(r"(A|An|The)\s+(.+)$", name)
        if m:
            name = m.group(2) + ", " + m.group(1)

        name = name.replace(" - ", ": ")
        return name


# ---------------------------------------------------------------------------
# XML Writer
# ---------------------------------------------------------------------------

class GamelistXmlWriter:
    """Builds and writes a miyoogamelist.xml file."""

    def __init__(self) -> None:
        self._entries: list[tuple[str, str, str]] = []

    def add_entry(self, rel_path: str, display_name: str, img_path: str) -> None:
        self._entries.append((rel_path, display_name, img_path))

    def write(self, output_path: str) -> None:
        lines = ['<?xml version="1.0"?>', "<gameList>"]
        for path, name, image in self._entries:
            lines.append("    <game>")
            lines.append(f"        <path>{html_escape(path, quote=False)}</path>")
            lines.append(f"        <name>{html_escape(name, quote=False)}</name>")
            lines.append(f"        <image>{html_escape(image, quote=False)}</image>")
            lines.append("    </game>")
        lines.append("</gameList>")
        with open(output_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")


# ---------------------------------------------------------------------------
# Gamelist Generator — main orchestrator
# ---------------------------------------------------------------------------

class GamelistGenerator:
    """Generates miyoogamelist.xml files for all ROM systems."""

    EXCLUDED_SYSTEMS = {
        "PORTS", "MAME2003PLUS", "ARCADE", "NEOGEO",
        "CPS1", "CPS2", "CPS3", "NAOMI", "ATOMISWAVE", "FFPLAY",
        "EASYRPG", "MSUMD", "SCUMMVM", "WOLF", "QUAKE", "DOOM",
    }

    SPECIAL_SYSTEMS = {
        "FBNEO",
    }

    # Patterns used by delete_gamelist_files to skip certain directories
    _DELETE_SKIP_PATTERNS = {".gamelists"} | EXCLUDED_SYSTEMS | SPECIAL_SYSTEMS

    def __init__(
        self,
        roms_dir: str,
        emu_dir: str,
        image_path: str = "",
        log_path: str = "",
    ) -> None:
        self.roms_dir = roms_dir
        self.emu_dir = emu_dir
        self.image_path = image_path
        self.log_path = log_path
        self._log_lines: list[str] = []

    # ---- public entry point ------------------------------------------------

    def _log(self, message: str) -> None:
        self._log_lines.append(message)

    def _write_log(self) -> None:
        if not self.log_path:
            return
        try:
            with open(self.log_path, "w", encoding="utf-8") as f:
                f.write("\n".join(self._log_lines) + "\n")
        except Exception:
            pass

    def generate_all(self) -> None:
        self._log_lines.clear()
        self._log("MiyooGamelist Generator")
        self._log("=" * 40)

        display_image_and_text(
            self.image_path,
            "Generating miyoogamelist.xml files...\n\n"
            "Please be patient, as this can take a few minutes.",
        )

        self._delete_gamelist_files()
        self._delete_cache_files()

        try:
            emu_entries = sorted(os.listdir(self.emu_dir))
        except FileNotFoundError:
            Display.display_message("Error: Emu directory not found", 500)
            self._log("ERROR: Emu directory not found")
            self._write_log()
            return

        generated = 0
        for system_name in emu_entries:
            system_path = os.path.join(self.emu_dir, system_name)
            if not os.path.isdir(system_path):
                continue

            if system_name in self.EXCLUDED_SYSTEMS:
                self._log(f"SKIP {system_name}: excluded system")
                continue

            extlist = self._get_extlist(system_name)
            if not extlist:
                self._log(f"SKIP {system_name}: no extlist found")
                continue

            # A system's ROMs may live under the canonical folder name or any of
            # its alternativeFolderNames; generate a gamelist for each that exists.
            rom_dirs = self._get_rom_dirs(system_name)
            if not rom_dirs:
                self._log(f"SKIP {system_name}: no ROM directory")
                continue

            for rom_path in rom_dirs:
                folder = os.path.basename(rom_path)
                display_image_and_text(
                    self.image_path,
                    f"Generating miyoogamelist.xml for {folder}...",
                )
                rom_count = self._generate_for_system(system_name, rom_path, extlist)
                self._log(f"OK   {system_name} ({folder}): {rom_count} ROMs")
                generated += 1

        self._log("=" * 40)
        self._log(f"Done. Generated gamelists for {generated} systems.")
        self._write_log()

        display_image_and_text(
            self.image_path,
            f"Done! Generated gamelists for {generated} systems.",
        )

        time.sleep(2)

    # ---- cleanup -----------------------------------------------------------

    def _delete_gamelist_files(self) -> None:
        """Remove existing miyoogamelist.xml from all non-excluded Roms dirs."""
        try:
            for system_dir in os.listdir(self.roms_dir):
                full_path = os.path.join(self.roms_dir, system_dir)
                if not os.path.isdir(full_path):
                    continue
                if any(pat in system_dir for pat in self._DELETE_SKIP_PATTERNS):
                    continue
                for root, _dirs, files in os.walk(full_path):
                    for f in files:
                        if f == "miyoogamelist.xml":
                            os.remove(os.path.join(root, f))
        except FileNotFoundError:
            pass

    def _delete_cache_files(self) -> None:
        """Remove *cache6.db files from all Roms dirs."""
        try:
            for root, _dirs, files in os.walk(self.roms_dir):
                for f in files:
                    if f.endswith("cache6.db"):
                        os.remove(os.path.join(root, f))
        except FileNotFoundError:
            pass

    # ---- helpers -----------------------------------------------------------

    def _get_extlist(self, system_name: str) -> set | None:
        """Read extension list from Emu/{system}/config.json."""
        config_path = os.path.join(self.emu_dir, system_name, "config.json")
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            raw = data.get("extlist", "")
            if not raw:
                return None
            return {ext for ext in raw.split("|") if ext}
        except (FileNotFoundError, json.JSONDecodeError, KeyError):
            return None

    def _get_rom_dirs(self, system_name: str) -> list:
        """Return every existing ROM directory for a system: the canonical
        Roms/{system} folder plus any alternativeFolderNames from config.json."""
        folder_names = [system_name]
        config_path = os.path.join(self.emu_dir, system_name, "config.json")
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            for alt in data.get("alternativeFolderNames", []) or []:
                if alt and alt not in folder_names:
                    folder_names.append(alt)
        except (FileNotFoundError, json.JSONDecodeError, KeyError):
            pass

        rom_dirs = []
        for folder in folder_names:
            candidate = os.path.join(self.roms_dir, folder)
            if os.path.isdir(candidate):
                rom_dirs.append(candidate)
        return rom_dirs

    # ---- per-system generation ---------------------------------------------

    def _generate_for_system(
        self, system_name: str, rom_path: str, extlist: set
    ) -> int:
        output_path = os.path.join(rom_path, "miyoogamelist.xml")

        # Pass 1: collect all ROM entries and detect duplicate cleaned names
        rom_entries: list[tuple[str, str, str, str]] = []
        name_count: dict[str, int] = {}
        self._collect_roms_recursive(
            rom_path, rom_path, "./Imgs", extlist, rom_entries, name_count
        )

        # Process special systems
        if system_name in self.SPECIAL_SYSTEMS:
            return self._generate_special(output_path, system_name, rom_entries)

        # Pass 2: write entries, using raw filename for ALL duplicates
        writer = GamelistXmlWriter()
        for file_rel_path, img_rel_path, dedup_key, filename_no_ext, cleaned in rom_entries:
            if name_count.get(dedup_key, 0) > 1:
                display_name = filename_no_ext
            else:
                display_name = cleaned
            writer.add_entry(file_rel_path, display_name, img_rel_path)

        writer.write(output_path)
        return len(rom_entries)

    def _collect_roms_recursive(
        self,
        current_dir: str,
        base_path: str,
        img_path: str,
        extlist: set,
        rom_entries: list,
        name_count: dict,
    ) -> None:
        try:
            entries = sorted(os.listdir(current_dir))
        except FileNotFoundError:
            return

        if current_dir == base_path:
            rel_path = ""
        else:
            rel_path = os.path.relpath(current_dir, base_path)

        for item_name in entries:
            item_full = os.path.join(current_dir, item_name)

            if os.path.isdir(item_full):
                if item_name == "Imgs" or item_name.startswith("."):
                    continue
                self._collect_roms_recursive(
                    item_full, base_path, img_path, extlist,
                    rom_entries, name_count,
                )
                continue

            if not os.path.isfile(item_full):
                continue

            # Check extension match (case-sensitive, matching bash case behaviour)
            dot_pos = item_name.rfind(".")
            if dot_pos < 0:
                continue
            ext = item_name[dot_pos + 1 :]
            if ext not in extlist:
                continue

            filename_no_ext = item_name[:dot_pos]

            # Build relative paths
            if not rel_path:
                file_rel_path = f"./{item_name}"
                img_rel_path = f"{img_path}/{filename_no_ext}.png"
            else:
                file_rel_path = f"./{rel_path}/{item_name}"
                img_rel_path = f"{img_path}/{rel_path}/{filename_no_ext}.png"

            # Clean name and track duplicates (keyed by subfolder)
            cleaned = RomNameCleaner.clean_name(item_name, extlist)
            if not cleaned:
                cleaned = filename_no_ext
            dedup_key = f"{rel_path}/{cleaned}" if rel_path else cleaned
            name_count[dedup_key] = name_count.get(dedup_key, 0) + 1

            rom_entries.append((file_rel_path, img_rel_path, dedup_key, filename_no_ext, cleaned))

    def _generate_special(
        self, output_path: str, system_name: str, rom_entries: str
    ) -> int:

        cancelled = False
        if os.path.exists(output_path):
            self._log(f"WAIT {system_name}: waiting for user input")

            while(True):
                Display.display_message(f"{system_name} gamelist file detected.\nDo you want to overwrite it?\n\nA = Accept, B = Cancel", 1)

                if(Controller.get_input()):
                    if(Controller.last_input() == ControllerInput.A):
                        # Backup last gamelist file, just in case
                        shutil.copy(output_path, f"{output_path}.bak")
                        break
                    if(Controller.last_input() == ControllerInput.B):
                        cancelled = True
                        break

        if cancelled:
            self._log(f"SKIP {system_name}: cancelled by user")
            return -1
        else:
            match system_name:
                case "FBNEO":
                    return self._generate_for_fbneo(output_path, rom_entries)
                case _:
                    return 0

    def _generate_for_fbneo(self, output_path: str, rom_entries: str) -> int:
        fbneo_csv = "/mnt/SDCARD/Emu/FBNEO/fbneo.csv"

        csvgames = {}
        with open(fbneo_csv, newline='') as csvfile:
            reader = csv.reader(csvfile)

            for row in reader:
                csvgames[row[0]] = row[1]

        games_c = 0
        game_writer = GamelistXmlWriter()
        for file_rel_path, img_rel_path, _, filename_no_ext, _ in rom_entries:
            try:
                display_name = csvgames[f"{filename_no_ext}.zip"]
                game_writer.add_entry(file_rel_path, display_name, img_rel_path)
                games_c += 1
            except KeyError:
                continue

        game_writer.write(output_path)

        return games_c

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    image_path = "/mnt/SDCARD/Themes/SPRUCE/icons/app/gamelist.png"
    roms_dir = "/mnt/SDCARD/Roms"
    emu_dir = "/mnt/SDCARD/Emu"
    log_path = "/mnt/SDCARD/App/MiyooGamelist/generate.log"

    generator = GamelistGenerator(roms_dir, emu_dir, image_path, log_path)
    generator.generate_all()

if __name__ == "__main__":
    main()
