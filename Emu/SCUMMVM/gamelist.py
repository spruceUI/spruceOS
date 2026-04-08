#!/usr/bin/env python3

"""
MiyooGamelist Generator for FBNEO.
"""

import time
from pathlib import Path

import sys
sys.path.insert(0, "/mnt/SDCARD/App/MiyooGamelist/")

from generate import PyUiMessenger, GamelistXmlWriter

# ---- helpers -----------------------------------------------------------

def get_id_from_file(fpath):
    with open(fpath) as f:
        return f.read()

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    scummvm_list = Path("/tmp/scvm_gameid.txt")
    roms_dir = Path("/mnt/SDCARD/Roms/SCUMMVM")
    output_xml = roms_dir.joinpath('miyoogamelist.xml')
    image_path = "/mnt/SDCARD/Themes/SPRUCE/icons/app/gamelist.png"

    messenger = PyUiMessenger()
    messenger.display_image_and_text(image_path, "Generating namelist...")
    time.sleep(1)

    # Parse scummvm --list-games output
    txtgames = {}
    with open(scummvm_list, newline='') as txtfile:
        for line in txtfile:
            if ":" in line:
                idx1 = line.find(":")
                idx2 = line.find(" ")

                gid = line[idx1+1:idx2]
                name = line[idx2:].strip()

                txtgames[gid] = name

    # Write XML
    games_c = 0
    game_writer = GamelistXmlWriter()
    for f in roms_dir.rglob("*.scummvm"):
        file_id = get_id_from_file(f)

        try:
            display_name = txtgames[file_id]
            img_path = f"./Imgs/{f.stem}.png"

            repl_path = str(f).replace(str(roms_dir), "")
            rel_path = f".{repl_path}"

            game_writer.add_entry(rel_path, display_name, img_path)
            games_c += 1
        except KeyError:
            continue

    game_writer.write(output_xml)

    messenger.display_image_and_text(image_path, f"{games_c} games found.")
    time.sleep(1)

if __name__ == "__main__":
    main()
