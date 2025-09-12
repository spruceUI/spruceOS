import json
import os
from PIL import Image
from utils.logger import PyUiLogger

class DaijishoThemeIndex:
    USE_DEFAULT = "USE_DEFAULT"

    def __init__(self, json_data):
        self.foldername = os.path.dirname(json_data)
        # Load from JSON string or dict
        with open(json_data, "r", encoding="utf-8") as f:
            self.data = json.load(f)

        self.default_filename = self.data.get("defaultWallpaperFilename")
        self.shortname_map = {}
        self.uniqueid_map = {}

        for entry in self.data.get("wallpaperList", []):
            shortname = entry.get("matchPlatformShortname")
            uniqueid = entry.get("matchPlatformUniqueId")
            filename = entry.get("filename")

            if shortname:
                self.shortname_map[shortname] = filename
            if uniqueid:
                self.uniqueid_map[uniqueid] = filename

        self.name_mapping = {
            "32x": ["sega32x"],
            "5200": ["atari5200"],
            "7800": ["atari7800"],
            "amiga": ["amiga"],
            #"arcade": [""],
            #"arduboy": [""],
            "atari": ["atari"],
            "atari800": ["atari800"],
            "atarist": ["atarist"],
            "c64": ["c64"],
            #"chai": ["aaaaa"],
            "col": ["coleco"],
            "cpc": ["cpc"],
            "cps1": ["cps1"],
            "cps2": ["cps2"],
            "cps3": ["cps3"],
            "dc": ["dreamcast"],
            "doom": ["doom"],
            "dos": ["dos"],
            "easyrpg": ["rpgmaker"],
            #"fairchild": ["aaaaa"],
            "fc": ["famicom","nes"],
            "fds": ["fds"],
            #"ffplay": ["aaaaa"],
            "gb": ["gb"],
            "gba": ["gba"],
            "gbc": ["gbc"],
            "gg": ["gamegear"],
            "gw": ["gw"],
            "itv": ["intellivision"],
            "lynx": ["lynx"],
            "mame": ["mame"],
            "md": ["genesis"],
            #"megaduck": ["aaaaa"],
            #"ms": ["aaaaa"],
            #"msu1": ["aaaaa"],
            #"msumd": ["aaaaa"],
            "msx": ["msx"],
            "n64": ["n64"],
            "nds": ["nds"],
            "neocd": ["neogeocd"],
            "neogeo": ["neogeo"],
            "ngp": ["ngp"],
            "ngpc": ["ngpc"],
            "ody": ["odyssey2"],
            "openbor": ["openbor"],
            "pce": ["pcengine"],
            "pcecd": ["pcengined"],
            "pico": ["pico8"],
            "poke": ["pokemini"],
            "ports": ["ports"],
            "ps": ["psx"],
            "psp": ["psp"],
            "quake": ["quake"],
            #"satella": ["aaaaa"],
            "saturn": ["saturn"],
            "scummvm": ["scummvm"],
            "segacd": ["segacd"],
            #"segasgone": ["aaaaa"],
            "sfc": ["sfamicom","snes"],
            "snes": ["sfamicom","snes"],
            #"sgb": ["aaaaa"],
            "sgfx": ["supergrafx"],
            #"sufami": ["aaaaa"],
            "supervision": ["supervision"],
            "tic": ["tic80"],
            "vb": ["virtualboy"],
            #"vdp": ["aaaaa"],
            "vectrex": ["vectrex"],
            #"wolf": ["aaaaa"],
            "ws": ["ws"],
            "wsc": ["wsc"],
            "x68000": ["x68000"],
            "zxs": ["zxspectrum"]
        }

    def _convert_if_needed(self, filename):
        # Check if filename ends with .jpg or .jpeg (case-insensitive)
        if filename.lower().endswith((".jpg", ".jpeg")):
            jpg_path = os.path.join(self.foldername, filename)
            png_filename = os.path.splitext(filename)[0] + ".png"
            png_path = os.path.join(self.foldername, png_filename)

            if not os.path.exists(png_path):
                PyUiLogger.get_logger().info(f"Converting {jpg_path} to {png_path}")
                try:
                    with Image.open(jpg_path) as img:
                        img.save(png_path, "PNG")
                except Exception as e:
                    raise RuntimeError(f"Failed to convert {jpg_path} to PNG: {e}")

            return png_path  # Return full path to PNG

        # For non-jpg/jpeg files, return full path to original file
        return os.path.join(self.foldername, filename)

    def get_file_name_for_system(self, system):
        if(system in self.name_mapping):
            names_to_try = self.name_mapping[system]
            for name in names_to_try:
                shortname = self.shortname_map.get(name)
                uniquename = self.uniqueid_map.get(name)
                if(shortname is not None):
                    return self._convert_if_needed(shortname)
                elif(uniquename is not None):
                    return self._convert_if_needed(uniquename)
        
        PyUiLogger.get_logger().info(f"No theme image found for {system}")
        return None

    def get_default_filename(self):
        return self._convert_if_needed(self.default_filename)