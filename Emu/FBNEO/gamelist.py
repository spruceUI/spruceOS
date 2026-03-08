#!/usr/bin/env python3

"""
MiyooGamelist Generator for FBNEO.
"""

import csv
import json
import socket
from pathlib import Path
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
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    fbneo_csv = Path("/mnt/SDCARD/Emu/FBNEO/fbneo.csv")
    roms_dir = Path("/mnt/SDCARD/Roms/FBNEO")
    output_xml = roms_dir.joinpath('miyoogamelist.xml')
    image_path = "/mnt/SDCARD/Themes/SPRUCE/icons/app/gamelist.png"

    messenger = PyUiMessenger()
    messenger.display_image_and_text(image_path, "Generating namelist...")

    csvgames = {}
    with open(fbneo_csv, newline='') as csvfile:
        reader = csv.reader(csvfile)

        for row in reader:
            csvgames[row[0]] = row[1]

    game_writer = GamelistXmlWriter()
    for f in roms_dir.iterdir():
        try:
            display_name = csvgames[f.name]
            img_path = f"./Imgs/{f.stem}.png"
            rel_path = f"./{f.name}"

            game_writer.add_entry(rel_path, display_name, img_path)
        except KeyError:
            continue

    game_writer.write(output_xml)

if __name__ == "__main__":
    main()
