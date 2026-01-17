import json
import os
from devices.device import Device
from utils.cached_exists import CachedExists
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
            "atari2600": ["atari2600"],
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
            "ms": ["master"],
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
            "satella": ["satellaview"],
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
        if(Device.get_device().supports_qoi()):
            if filename.lower().endswith((".jpg", ".jpeg")):
                jpg_path = os.path.join(self.foldername, filename)
                qoi_filename = os.path.splitext(filename)[0] + ".qoi"
                qoi_path = os.path.join(self.foldername, qoi_filename)
                if CachedExists.exists(qoi_path):
                    return qoi_path

                if not CachedExists.exists(qoi_path):
                    PyUiLogger.get_logger().info(f"Converting {jpg_path} to {qoi_path}")
                    try:
                        Device.get_device().get_image_utils().convert_from_jpg_to_qoi(jpg_path, qoi_path)
                    except Exception as e:
                        PyUiLogger.get_logger().warning(
                            f"Failed to convert {jpg_path} to PNG: {e}"
                        )
                        return jpg_path  # fallback: return original JPG

                return qoi_path  # Return full path to PNG
        else:
            if filename.lower().endswith((".jpg", ".jpeg")):
                jpg_path = os.path.join(self.foldername, filename)
                png_filename = os.path.splitext(filename)[0] + ".png"
                png_path = os.path.join(self.foldername, png_filename)
                if CachedExists.exists(png_path):
                    return png_path

                if not CachedExists.exists(png_path):
                    PyUiLogger.get_logger().info(f"Converting {jpg_path} to {png_path}")
                    try:
                        Device.get_device().get_image_utils().convert_from_jpg_to_png(jpg_path, png_path)
                    except Exception as e:
                        PyUiLogger.get_logger().warning(
                            f"Failed to convert {jpg_path} to PNG: {e}"
                        )
                        return jpg_path  # fallback: return original JPG

                return png_path  # Return full path to PNG

        # For non-jpg/jpeg files, return full path to original file
        return os.path.join(self.foldername, filename)


    def get_file_name_for_system(self, system):
        #PyUiLogger.get_logger().info(f"Looking up {system}")
        if(system in self.name_mapping):
            names_to_try = self.name_mapping[system]
            for name in names_to_try:
                shortname = self.shortname_map.get(name)
                uniquename = self.uniqueid_map.get(name)
                if(shortname is not None):
                    file_name = self._convert_if_needed(shortname)
                    #PyUiLogger.get_logger().info(f"Returning {file_name} for {system}")
                    return file_name
                elif(uniquename is not None):
                    file_name = self._convert_if_needed(uniquename)
                    #PyUiLogger.get_logger().info(f"Returning {file_name} for {system}")
                    return file_name
        
        #PyUiLogger.get_logger().info(f"No theme image found for {system}")
        return self.get_default_filename()

    def get_default_filename(self):
        return self._convert_if_needed(self.default_filename)