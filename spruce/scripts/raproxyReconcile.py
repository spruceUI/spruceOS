# Usage: raproxyReconcile.py [rom_file_path game_system_name display_name]
# Run through raproxy_reconcile so the app's environment is in place.
#
# The daemon caches every game it proxies while online, which PyUI's list
# never sees. Make the daemon's list the truth: drop entries it no longer
# has, attribute a single new game to the ROM that just ran, and list the
# rest by title so they can be removed.
import json
import os
import sys
import tempfile

from raofflineproxy.config import DATABASE_FILE
from raofflineproxy.rom_browser import list_cached_games
from raofflineproxy.storage import Storage

CACHE_JSON = "/mnt/SDCARD/Saves/pyui-cheevos-cache.json"


def load():
    try:
        with open(CACHE_JSON) as f:
            return [e for e in json.load(f) if isinstance(e, dict)]
    except (OSError, ValueError):
        return []


def save(entries):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(CACHE_JSON), suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(entries, f, indent=4)
    os.replace(tmp, CACHE_JSON)


def main():
    if not DATABASE_FILE.exists():
        return
    rom, system, name = (sys.argv[1:4] + [None] * 3)[:3]

    games = {g.game_id: g.title for g in list_cached_games(Storage())}
    entries = [e for e in load() if e.get("game_id") is None or e["game_id"] in games]
    known = {e["game_id"] for e in entries if e.get("game_id") is not None}
    new = [gid for gid in games if gid not in known]

    rom_has_id = any(e.get("rom_file_path") == rom and e.get("game_id") is not None
                     for e in entries)
    if rom and len(new) == 1 and not rom_has_id:
        entries = [e for e in entries if e.get("rom_file_path") != rom]
        entries.append({"rom_file_path": rom, "game_system_name": system,
                        "display_name": name, "game_id": new[0]})
    else:
        for gid in new:
            entries.append({"rom_file_path": None, "game_system_name": None,
                            "display_name": games[gid], "game_id": gid})

    save(entries)
    print(f"{len(new)} new, {len(entries)} listed")


main()
