"""Which ScreenScraper box to take when a game has one per region.

Ported from Spruce Scraper's "Auto" choice (CatalyticArkun, MIT): regions named in the file
name come first ("Game (Europe).zip" gets the European box), then the chain for spruce's
preferredRegion, then everything else in ScreenScraper's usual order.
"""

import re
from typing import List

# Skyscraper's default order; every list ends with whatever it leaves out
DEFAULT = [
    "eu", "us", "ss", "uk", "wor", "jp", "au", "ame", "de", "cus", "cn", "kr", "asi", "br", "sp",
    "fr", "gr", "it", "no", "dk", "nz", "nl", "pl", "ru", "se", "tw", "ca",
]

FIRST = {
    "us": ["us", "wor", "ame", "ca", "ss", "eu", "uk", "au"],
    "eu": ["eu", "wor", "uk", "de", "fr", "sp", "it", "au", "ss", "us"],
    "jp": ["jp", "wor", "asi", "ss", "us", "eu"],
    "wor": ["wor", "us", "eu", "ss", "uk", "jp"],
}

# No-Intro / Redump region words -> ScreenScraper region keys
NAME_REGIONS = {
    "usa": "us", "europe": "eu", "japan": "jp", "world": "wor", "uk": "uk",
    "united kingdom": "uk", "germany": "de", "france": "fr", "spain": "sp", "italy": "it",
    "australia": "au", "korea": "kr", "china": "cn", "brazil": "br", "asia": "asi",
    "canada": "ca", "taiwan": "tw", "netherlands": "nl", "sweden": "se", "russia": "ru",
    "poland": "pl", "denmark": "dk", "norway": "no", "greece": "gr", "new zealand": "nz",
}

_TAG = re.compile(r"\(([^()]*)\)")


def key_for_spruce(value) -> str:
    """Region key for spruce's preferredRegion ("USA", "EUROPE", "JAPAN", "WORLD", ...)."""
    v = value.upper() if isinstance(value, str) else ""
    if "EUR" in v or v == "EU":
        return "eu"
    if "JAP" in v or v in ("JPN", "JP"):
        return "jp"
    if "WORLD" in v or v == "WOR":
        return "wor"
    return "us"


def regions_in_name(rom_name: str) -> List[str]:
    """Region keys named in the ROM's tags, in the order they appear."""
    found = []
    for tag in _TAG.findall(rom_name):
        for word in tag.split(","):
            key = NAME_REGIONS.get(word.strip().lower())
            if key and key not in found:
                found.append(key)
    return found


def priorities(rom_name: str, spruce_region) -> List[str]:
    out = []
    for key in regions_in_name(rom_name) + FIRST[key_for_spruce(spruce_region)] + DEFAULT:
        if key not in out:
            out.append(key)
    return out
