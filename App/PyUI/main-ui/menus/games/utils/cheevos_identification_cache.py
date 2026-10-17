"""Remember game IDs for paths Spruce hasn't identified, across app handoffs."""

import json
import os
import tempfile
import time

CACHE_FILE = "/mnt/SDCARD/Saves/cheevos/cache/rom-identifications.json"
MAX_ENTRIES = 256
MAX_CACHE_BYTES = 256 * 1024
MISS_TTL = 7 * 24 * 60 * 60


def valid_result(result):
    """Accept only confirmed misses or valid positive game IDs."""
    return isinstance(result, dict) and (
        result.get("status") == "no_match"
        or (
            result.get("status") == "matched"
            and type(result.get("game_id")) is int
            and result["game_id"] > 0
        )
    )


class IdentificationCache:
    """Keep bounded path associations; known games remain usable after a ROM is patched."""

    def __init__(self, path=None):
        self.path = path or CACHE_FILE
        self.entries = {}
        try:
            if os.path.getsize(self.path) > MAX_CACHE_BYTES:
                return
            with open(self.path) as source:
                payload = json.load(source)
            # Read the earlier fingerprint format too, discarding its obsolete metadata.
            if not isinstance(payload, dict) or payload.get("version") not in (1, 2):
                return
            entries = payload.get("entries")
            if not isinstance(entries, dict) or len(entries) > MAX_ENTRIES:
                return
            for key, entry in entries.items():
                if not isinstance(entry, dict) or not valid_result(entry.get("result")):
                    continue
                self.entries[key] = {"result": entry["result"]}
                if entry["result"]["status"] == "no_match":
                    self.entries[key]["checked_at"] = entry.get("checked_at")
        except (OSError, ValueError):
            pass

    def lookup(self, path):
        """Return the known game for this path, or a confirmed miss younger than one week."""
        entry = self.entries.get(os.path.abspath(path))
        if entry is None:
            return None
        result = entry["result"]
        if result["status"] == "no_match":
            checked_at = entry.get("checked_at")
            if type(checked_at) not in (int, float) or not 0 <= time.time() - checked_at < MISS_TTL:
                return None
        return result

    def remember(self, path, result):
        """Persist helper outcomes atomically; cache write failures never block launch."""
        if not valid_result(result):
            return
        key = os.path.abspath(path)
        self.entries.pop(key, None)
        self.entries[key] = {"result": result}
        if result["status"] == "no_match":
            self.entries[key]["checked_at"] = time.time()
        while len(self.entries) > MAX_ENTRIES:
            del self.entries[next(iter(self.entries))]
        temporary = None
        try:
            directory = os.path.dirname(self.path)
            os.makedirs(directory, exist_ok=True)
            with tempfile.NamedTemporaryFile(mode="w", dir=directory, delete=False) as output:
                temporary = output.name
                json.dump({"version": 2, "entries": self.entries}, output, separators=(",", ":"))
            if os.path.getsize(temporary) <= MAX_CACHE_BYTES:
                os.replace(temporary, self.path)
        except (OSError, ValueError):
            pass
        finally:
            if temporary is not None:
                try:
                    os.unlink(temporary)
                except OSError:
                    pass
