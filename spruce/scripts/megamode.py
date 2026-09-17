"""Boot into a random Mega Man game.

Usage: megamode.py [--refresh] <platform> <device name>...

Scans like PyUI's MiyooTrimGameSystemUtils and RomUtils, so it only picks
games PyUI would list on this device. The cache is keyed by folder mtimes,
and is per platform because the card moves between devices.
"""

import json
import os
import random
import re
import subprocess
import sys

EMU_DIR = "/mnt/SDCARD/Emu"
ROMS_PATHS = ["/mnt/SDCARD/Roms", "/media/sdcard1/Roms"]
CACHE_DIR = "/mnt/SDCARD/Saves/cache"
CMD_TO_RUN = "/tmp/cmd_to_run.sh"

NAME_MATCH = re.compile(r"mega[ ._-]?man|rockman", re.IGNORECASE)
NAME_EXCLUDE = re.compile(r"megamania", re.IGNORECASE)


def load_config(system):
    try:
        with open(os.path.join(EMU_DIR, system, "config.json"), encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def system_is_active(config, device_names):
    devices = config.get("devices") or []
    if devices and not any(name in devices for name in device_names):
        return False
    for group in config.get("requiredfiles") or []:
        if not any(os.path.exists(path) for path in group):
            return False
    return True


def list_dir(path):
    try:
        return set(os.listdir(path))
    except OSError:
        return set()


# Matched against listdir like PyUI's CachedExists: the card is case-insensitive,
# so os.path.exists would also accept "fc" for "FC" and scan it twice
def rom_folders(system, config, roms_entries):
    names = [system] + list(config.get("alternativeFolderNames") or [])
    return [os.path.join(base, name) for base in ROMS_PATHS for name in names
            if name in roms_entries[base]]


def scan_folder(folder, config, launch_path, dirs, games):
    try:
        dirs[folder] = os.stat(folder).st_mtime_ns
        entries = list(os.scandir(folder))
    except OSError:
        return

    extlist = {f".{ext}" for ext in (config.get("extlist") or "").lower().split("|") if ext}
    ignore = set(config.get("ignoreList") or [])
    scan_subfolders = config.get("scanSubfolders", True)

    for entry in entries:
        name = entry.name
        if name.startswith("."):
            continue
        try:
            is_dir = entry.is_dir()
        except OSError:
            is_dir = False

        if is_dir:
            if scan_subfolders and name != "Imgs":
                scan_folder(entry.path, config, launch_path, dirs, games)
            continue

        dot = name.rfind(".")
        suffix = name[dot:].lower() if dot != -1 else ""
        if extlist:
            if suffix not in extlist:
                continue
        elif name.endswith((".xml", ".txt", ".db")):
            continue
        if name in ignore:
            continue
        if NAME_MATCH.search(name) and not NAME_EXCLUDE.search(name):
            games.append([entry.path, launch_path])


def scan(device_names):
    dirs = {}
    games = []
    for base in ROMS_PATHS:
        if os.path.isdir(base):
            dirs[base] = os.stat(base).st_mtime_ns
    roms_entries = {base: list_dir(base) for base in ROMS_PATHS}

    try:
        systems = sorted(name for name in os.listdir(EMU_DIR)
                         if os.path.isdir(os.path.join(EMU_DIR, name)))
    except OSError:
        systems = []

    for system in systems:
        config = load_config(system)
        if config is None or not system_is_active(config, device_names):
            continue
        launch_path = os.path.join(EMU_DIR, system, config.get("launch") or "")
        for folder in rom_folders(system, config, roms_entries):
            scan_folder(folder, config, launch_path, dirs, games)

    return {"dirs": dirs, "games": games}


def dirs_unchanged(cache):
    for folder, mtime in cache.get("dirs", {}).items():
        try:
            if os.stat(folder).st_mtime_ns != mtime:
                return False
        except OSError:
            return False
    # A card inserted in the second slot since the last scan
    return all(base in cache["dirs"] for base in ROMS_PATHS if os.path.isdir(base))


def load_cache(path):
    try:
        with open(path, encoding="utf-8") as f:
            cache = json.load(f)
        if isinstance(cache.get("dirs"), dict) and isinstance(cache.get("games"), list):
            return cache
    except Exception:
        pass
    return None


def save_cache(path, cache):
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cache, f)
    os.replace(tmp, path)


def pick(games):
    games = list(games)
    while games:
        game = games.pop(random.randrange(len(games)))
        if os.path.isfile(game[0]):
            return game
    return None


def write_cmd_to_run(game):
    rom_path, launch_path = game
    escaped = re.sub(r'([$`"\\])', r"\\\1", rom_path)
    with open(CMD_TO_RUN, "w") as f:
        f.write(f'chmod a+x "{launch_path}";"{launch_path}" "{escaped}"')


def refresh_in_background(platform, device_names):
    subprocess.Popen(
        [sys.executable, os.path.abspath(__file__), "--refresh", platform] + device_names,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True, preexec_fn=lambda: os.nice(19))


def main():
    args = sys.argv[1:]
    refresh = bool(args) and args[0] == "--refresh"
    if refresh:
        args = args[1:]
    if len(args) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    platform, device_names = args[0], args[1:]
    cache_path = os.path.join(CACHE_DIR, f"megamode_{platform}.json")

    if refresh:
        save_cache(cache_path, scan(device_names))
        return 0

    cache = load_cache(cache_path)
    fresh = cache is None or not dirs_unchanged(cache)
    if fresh:
        cache = scan(device_names)
        save_cache(cache_path, cache)

    game = pick(cache["games"])
    if game is None and not fresh:
        cache = scan(device_names)
        save_cache(cache_path, cache)
        fresh = True
        game = pick(cache["games"])

    if game is None:
        print("Mega Mode: no games found")
        return 1

    write_cmd_to_run(game)
    print(f"Mega Mode: {game[0]} ({len(cache['games'])} cached)")

    # Folder mtimes can't be fully trusted (archive tools reset them), so like
    # PyUI's RomListVerifier, a cached answer is re-checked in the background
    if not fresh:
        refresh_in_background(platform, device_names)
    return 0


if __name__ == "__main__":
    sys.exit(main())
