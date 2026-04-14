#!/usr/bin/env python3

"""
MiyooGamelist Generator for FBNEO.
"""

import csv
import time
from pathlib import Path

import sys
sys.path.insert(0, "/mnt/SDCARD/App/MiyooGamelist/")

from generate import PyUiMessenger, GamelistXmlWriter

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
    time.sleep(1)

    csvgames = {}
    with open(fbneo_csv, newline='') as csvfile:
        reader = csv.reader(csvfile)

        for row in reader:
            csvgames[row[0]] = row[1]

    games_c = 0
    game_writer = GamelistXmlWriter()
    for f in roms_dir.iterdir():
        try:
            display_name = csvgames[f.name]
            img_path = f"./Imgs/{f.stem}.png"
            rel_path = f"./{f.name}"

            game_writer.add_entry(rel_path, display_name, img_path)
            games_c += 1
        except KeyError:
            continue

    game_writer.write(output_xml)

    messenger.display_image_and_text(image_path, f"{games_c} games found.")
    time.sleep(1)

if __name__ == "__main__":
    main()
