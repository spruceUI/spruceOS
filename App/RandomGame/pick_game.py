#!/usr/bin/env python3
# Prints the path of a random game, chosen the way PyUI lists games.
import json
import os
import random
import sys

ROMS = "/mnt/SDCARD/Roms"
EMU = "/mnt/SDCARD/Emu"
HISTORY = "/mnt/SDCARD/App/RandomGame/5_previous.txt"
REMEMBER = 5


def system_filter(system):
    try:
        with open(os.path.join(EMU, system, "config.json")) as f:
            cfg = json.load(f)
    except (OSError, ValueError):
        return None
    exts = {"." + e.lower() for e in (cfg.get("extlist") or "").split("|") if e}
    return exts, set(cfg.get("ignoreList") or [])


def games(folder, exts, ignore):
    found = []
    try:
        with os.scandir(folder) as entries:
            for entry in entries:
                name = entry.name
                if name.startswith(".") or name in ignore or not entry.is_file():
                    continue
                suffix = os.path.splitext(name)[1].lower()
                if exts:
                    if suffix in exts:
                        found.append(entry.path)
                elif suffix not in (".xml", ".txt", ".db"):
                    found.append(entry.path)
    except OSError:
        pass
    return found


def main():
    try:
        with open(HISTORY) as f:
            recent = [line.rstrip("\n") for line in f if line.strip()]
    except OSError:
        recent = []

    pool = []
    try:
        systems = os.listdir(ROMS)
    except OSError:
        return 1
    for system in systems:
        rule = system_filter(system)
        if rule is None:
            continue
        pool.extend(games(os.path.join(ROMS, system), *rule))

    fresh = [g for g in pool if g not in recent] or pool
    if not fresh:
        return 1

    pick = random.choice(fresh)
    try:
        with open(HISTORY, "w") as f:
            f.write("".join(g + "\n" for g in (recent + [pick])[-REMEMBER:]))
    except OSError:
        pass
    print(pick)
    return 0


if __name__ == "__main__":
    sys.exit(main())
