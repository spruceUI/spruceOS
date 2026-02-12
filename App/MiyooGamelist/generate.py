#!/usr/bin/env python3
"""
MiyooGamelist Generator — generates miyoogamelist.xml files for ROM systems.

Replaces generate.sh + functions.sh with portable Python 3.10 code.
Sends progress messages to PyUI via TCP socket on port 50980.
"""

import json
import os
import re
import socket
from html import escape as html_escape


# ---------------------------------------------------------------------------
# PyUI Messenger — progress display via TCP socket
# ---------------------------------------------------------------------------

class PyUiMessenger:
    """Sends display messages to the PyUI realtime listener on port 50980."""

    HOST = "127.0.0.1"
    PORT = 50980

    def send_message(self, json_str: str) -> None:
        try:
            with socket.create_connection((self.HOST, self.PORT), timeout=1) as s:
                s.sendall((json_str + "\n").encode("utf-8"))
        except Exception:
            pass

    def display_image_and_text(
        self,
        image_path: str,
        text: str,
        size: int = 35,
        img_y: int = 25,
        text_y: int = 75,
    ) -> None:
        msg = json.dumps({
            "cmd": "IMAGE_AND_TEXT",
            "args": [image_path, text, str(size), str(img_y), str(text_y)],
        })
        self.send_message(msg)

    def display_text(self, text: str) -> None:
        msg = json.dumps({"cmd": "MESSAGE", "args": [text]})
        self.send_message(msg)


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
        7. Move trailing articles to front ("Game, The" -> "The Game")
        8. Replace " - " with ": "
        """
        name = RomNameCleaner.strip_extensions(filename, extlist)
        name = re.sub(r"\([^)]*\)", "", name)
        name = re.sub(r"\[[^\]]*\]", "", name)
        name = re.sub(r"^[0-9]+\.", "", name)
        name = name.replace("_", " ")
        name = " ".join(name.split())

        m = re.search(r",\s+(A|The|An)$", name)
        if m:
            article = m.group(1)
            name = article + " " + re.sub(r",\s+(A|The|An)$", "", name)

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
        "PORTS", "FBNEO", "MAME2003PLUS", "ARCADE", "NEOGEO",
        "CPS1", "CPS2", "CPS3", "FFPLAY", "EASYRPG", "MSUMD",
        "SCUMMVM", "WOLF", "QUAKE", "DOOM",
    }

    # Patterns used by delete_gamelist_files to skip certain directories
    _DELETE_SKIP_PATTERNS = {".gamelists"} | EXCLUDED_SYSTEMS

    def __init__(
        self,
        roms_dir: str,
        emu_dir: str,
        messenger: PyUiMessenger,
        image_path: str = "",
    ) -> None:
        self.roms_dir = roms_dir
        self.emu_dir = emu_dir
        self.messenger = messenger
        self.image_path = image_path

    # ---- public entry point ------------------------------------------------

    def generate_all(self) -> None:
        self.messenger.display_image_and_text(
            self.image_path,
            "Generating miyoogamelist.xml files...\n\n"
            "Please be patient, as this can take a few minutes.",
        )

        self._delete_gamelist_files()
        self._delete_cache_files()

        try:
            emu_entries = sorted(os.listdir(self.emu_dir))
        except FileNotFoundError:
            self.messenger.display_text("Error: Emu directory not found")
            return

        for system_name in emu_entries:
            system_path = os.path.join(self.emu_dir, system_name)
            if not os.path.isdir(system_path):
                continue
            if system_name in self.EXCLUDED_SYSTEMS:
                continue

            extlist = self._get_extlist(system_name)
            if not extlist:
                continue

            rom_path = os.path.join(self.roms_dir, system_name)
            if not os.path.isdir(rom_path):
                continue

            self.messenger.display_image_and_text(
                self.image_path,
                f"Generating miyoogamelist.xml for {system_name}...",
            )
            self._generate_for_system(system_name, rom_path, extlist)

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

    # ---- per-system generation ---------------------------------------------

    def _generate_for_system(
        self, system_name: str, rom_path: str, extlist: set
    ) -> None:
        output_path = os.path.join(rom_path, "miyoogamelist.xml")
        writer = GamelistXmlWriter()
        used_names: set[str] = set()
        self._process_roms_recursive(
            rom_path, rom_path, "./Imgs", extlist, writer, used_names
        )
        writer.write(output_path)

    def _process_roms_recursive(
        self,
        current_dir: str,
        base_path: str,
        img_path: str,
        extlist: set,
        writer: GamelistXmlWriter,
        used_names: set,
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
                self._process_roms_recursive(
                    item_full, base_path, img_path, extlist, writer, used_names
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

            # Clean name
            cleaned = RomNameCleaner.clean_name(item_name, extlist)

            # Duplicate detection (keyed by subfolder to avoid cross-folder collisions)
            dedup_key = f"{rel_path}/{cleaned}" if rel_path else cleaned
            if dedup_key in used_names:
                display_name = filename_no_ext
            else:
                display_name = cleaned
                used_names.add(dedup_key)

            writer.add_entry(file_rel_path, display_name, img_rel_path)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    image_path = "/mnt/SDCARD/Themes/SPRUCE/icons/app/gamelist.png"
    roms_dir = "/mnt/SDCARD/Roms"
    emu_dir = "/mnt/SDCARD/Emu"

    messenger = PyUiMessenger()
    generator = GamelistGenerator(roms_dir, emu_dir, messenger, image_path)
    generator.generate_all()


if __name__ == "__main__":
    main()
