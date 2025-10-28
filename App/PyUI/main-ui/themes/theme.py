import json
import logging
import os
import sys
import traceback

from devices.charge.charge_status import ChargeStatus
from devices.device import Device
from devices.wifi.wifi_status import WifiStatus
from display.font_purpose import FontPurpose
from display.resize_type import ResizeType
from menus.games.utils.daijisho_theme_index import DaijishoThemeIndex
from themes.theme_patcher import ThemePatcher
from utils.logger import PyUiLogger
from views.view_type import ViewType

class Theme():
    _data = {}
    _path = ""
    _skin_folder = ""
    _icon_folder = ""
    _loaded_file_path = ""
    _daijisho_theme_index = None

    _default_multiplier = 1.0

    @classmethod
    def init(cls, path, width, height):
        cls.set_theme_path(path, width, height)

    @classmethod
    def set_theme_path(cls,path, width = 0, height = 0):
        cls.load_defaults_so_user_can_see_at_least(path)

        resolution_specific_config = f"config_{width}x{height}.json"
        config_path = os.path.join(path, resolution_specific_config)
        if os.path.exists(config_path):
            PyUiLogger.get_logger().info(f"Resolution specific config found, using {resolution_specific_config}")
        else:
            config_path = "config.json"
            PyUiLogger.get_logger().info(f"No resolution specific config {config_path} found, using config.json")


        cls._data.clear()
        cls._path = path
        cls._load_defaults()
        cls._load_from_file(os.path.join(path, config_path))

        cls._path = path
        cls._skin_folder = cls._get_asset_folder("skin", width, height)
        cls._icon_folder = cls._get_asset_folder("icons", width, height)
        daijisho_theme_index_file = os.path.join(cls._path, cls._icon_folder,"index.json")
        if os.path.exists(daijisho_theme_index_file):
            try:
                cls._daijisho_theme_index = DaijishoThemeIndex(daijisho_theme_index_file)
                PyUiLogger.get_logger().info(f"Using DaijishoThemeIndex from {daijisho_theme_index_file}")
            except Exception:
                PyUiLogger.get_logger().error(f"Failed to load DaijishoThemeIndex from {daijisho_theme_index_file}:")
                logging.exception(f"Failed to load DaijishoThemeIndex from {daijisho_theme_index_file}")
                cls._daijisho_theme_index = None
        else:
            PyUiLogger.get_logger().info(f"DaijishoThemeIndex does not exist at: {daijisho_theme_index_file} (Assuming non daijisho theme)")
            cls._daijisho_theme_index = None

        scale_width = Device.screen_width() / width
        scale_height = Device.screen_height() / height
        cls._default_multiplier = min(scale_width, scale_height)


    @classmethod
    def convert_theme_if_needed(cls, path, width, height):
        resolution_specific_config = f"config_{width}x{height}.json"
        config_path = os.path.join(path, resolution_specific_config)

        resolution_converted = False
        if os.path.exists(config_path):
            PyUiLogger.get_logger().info(f"Resolution specific config found, using {resolution_specific_config}")
        elif ThemePatcher.patch_theme(path,width, height) and os.path.exists(config_path):
            resolution_converted = True

        tga_converted = ThemePatcher.convert_to_tga(path)

        if(resolution_converted or tga_converted):
            cls.set_theme_path(path,width,height)

    @classmethod
    def load_defaults_so_user_can_see_at_least(cls, path):
        cls._data.clear()
        cls._path = path
        cls._load_defaults()

        cls._load_from_file(os.path.join(path, "config.json"))

        cls._path = path
        cls._skin_folder = cls._get_asset_folder("skin", -1, -1)
        cls._icon_folder = cls._get_asset_folder("icons", -1, -1)

    @classmethod
    def get_theme_path(cls):
        return cls._path

    @classmethod
    def _get_asset_folder(cls, base_folder, width, height):
        folder = f"{base_folder}_{width}x{height}"
        full_path = os.path.join(cls._path, folder)
        if os.path.isdir(full_path):
            PyUiLogger.get_logger().info(f"Resolution specific assets found, using {folder}")
            return folder
        else:
            PyUiLogger.get_logger().info(f"No resolution specific assets {folder} found, using {base_folder}")
            return base_folder

    @classmethod
    def _load_defaults(cls):
        cls._data["showBottomBar"] = True

    @classmethod
    def _load_from_file(cls, file_path):
        try:
            cls._loaded_file_path = file_path
            with open(file_path, 'r', encoding='utf-8') as f:
                cls._data.update(json.load(f))
            desc = cls._data.get("description", "UNKNOWN")
            PyUiLogger.get_logger().info(f"Loaded Theme : {desc}")
        except Exception as e:
            PyUiLogger.get_logger().error(
                f"Unexpected error while loading {file_path}: {e}\n{traceback.format_exc()}"
            )
            Device.get_system_config().delete_theme_entry()
            raise

    @classmethod
    def save_changes(cls):
        data = {
            key: value for key, value in cls._data.items()
            if not key.startswith('_') and not callable(value)
        }
        with open(cls._loaded_file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
        PyUiLogger.get_logger().info(f"Wrote Theme : {cls._data.get('description', 'UNKNOWN')}")
        from display.display import Display
        Display.clear_cache()

    @classmethod
    def _asset(cls, *parts):
        path = os.path.join(cls._path, cls._skin_folder, *parts)
        # If the file doesn't exist and ends with .tga, try the PNG fallback
        if not os.path.exists(path) or not Device.supports_tga():
            png_path = path[:-4] + ".png" 
            if os.path.exists(png_path):
                return png_path

        # Otherwise return the original path
        return path
        
    @classmethod
    def _icon(cls, *parts):
        path = os.path.join(cls._path, cls._icon_folder, *parts)
        # If the file doesn't exist and ends with .tga, try the PNG fallback
        if not os.path.exists(path) or not Device.supports_tga():
            png_path = path[:-4] + ".png" 
            if os.path.exists(png_path):
                return png_path

        # Otherwise return the original path
        return path

    @classmethod
    def background(cls, page = None):
        if(page is None):
            return cls._asset("background.tga")
        else:
            return cls._asset(f"{page.lower()}-background.tga")
    
    @classmethod
    def favorite(cls): return cls._asset("ic-favorite-n.tga")
    
    @classmethod
    def favorite_selected(cls): return cls._asset("ic-favorite-f.tga")
    
    @classmethod
    def recent(cls): return cls._asset("ic-recent-n.tga")
    
    @classmethod
    def recent_selected(cls): return cls._asset("ic-recent-f.tga")

    @classmethod
    def collection(cls): return cls._asset("ic-collection-n.tga")
    
    @classmethod
    def collection_selected(cls): return cls._asset("ic-collection-f.tga")
    
    @classmethod
    def game(cls): return cls._asset("ic-game-n.tga")
    
    @classmethod
    def game_selected(cls): return cls._asset("ic-game-f.tga")
    
    @classmethod
    def app(cls): return cls._asset("ic-app-n.tga")
    
    @classmethod
    def app_selected(cls): return cls._asset("ic-app-f.tga")
    
    @classmethod
    def settings(cls): return cls._asset("ic-setting-n.tga")
    
    @classmethod
    def settings_selected(cls): return cls._asset("ic-setting-f.tga")
    
    @classmethod
    def get_title_bar_bg(cls): return cls._asset("bg-title.tga")
    
    @classmethod
    def bottom_bar_bg(cls): return cls._asset("tips-bar-bg.tga")
    
    @classmethod
    def confirm_icon(cls): return cls._asset("icon-A-54.tga")
    
    @classmethod
    def back_icon(cls): return cls._asset("icon-B-54.tga")
    
    @classmethod
    def start_icon(cls): return cls._asset("icon-START.tga")
    
    @classmethod
    def show_bottom_bar(cls): return cls._data.get("showBottomBar", True) is not False
    
    @classmethod
    def ignore_top_and_bottom_bar_for_layout(cls): return cls._data.get("ignoreTopAndBottomBarForLayout", False)
    
    @classmethod
    def show_top_bar_text(cls): return cls._data.get("showTopBarText", True)
    
    @classmethod
    def render_top_and_bottom_bar_last(cls): return cls._data.get("renderTopAndBottomBarLast", False)
    
    @classmethod
    def confirm_text(cls): return "Okay"
    
    @classmethod
    def back_text(cls): return "Back"
    
    @classmethod
    def favorite_icon(cls): return cls._asset("ic-favorite-mark.tga")
    
    @classmethod
    def get_list_large_selected_bg(cls): return cls._asset("bg-list-l.tga")
   
    @classmethod
    def menu_popup_bg_large(cls): return cls._asset("bg-pop-menu-4.tga")
    
    @classmethod
    def keyboard_bg(cls): return cls._asset("bg-grid-s.tga")
    
    @classmethod
    def keyboard_entry_bg(cls): return cls._asset("bg-list-l.tga")
    
    @classmethod
    def key_bg(cls): return cls._asset("bg-btn-01-n.tga")
    
    @classmethod
    def key_selected_bg(cls): return cls._asset("bg-btn-01-f.tga")
    
    @classmethod
    def get_list_small_selected_bg(cls): return cls._asset("bg-list-s.tga")
    
    @classmethod
    def get_popup_menu_selected_bg(cls): return cls._asset("bg-list-s2.tga")
    
    @classmethod
    def get_missing_image_path(cls): return cls._asset("missing_image.tga")
    
    @classmethod
    def get_battery_icon(cls, charging, battery_percent):
        if ChargeStatus.CHARGING == charging:
            if battery_percent > 97:
                return cls._asset("ic-power-charge-100%.tga")
            elif battery_percent >= 75:
                return cls._asset("ic-power-charge-75%.tga")
            elif battery_percent >= 50:
                return cls._asset("ic-power-charge-50%.tga")
            elif battery_percent >= 25:
                return cls._asset("ic-power-charge-25%.tga")
            else:
                return cls._asset("ic-power-charge-0%.tga")
        else:
            if battery_percent >= 97:
                return cls._asset("power-full-icon.tga")
            elif battery_percent >= 80:
                return cls._asset("power-80%-icon.tga")
            elif battery_percent >= 50:
                return cls._asset("power-50%-icon.tga")
            elif battery_percent >= 20:
                return cls._asset("power-20%-icon.tga")
            else:
                return cls._asset("power-0%-icon.tga")
            
    @classmethod
    def get_wifi_icon(cls, status):
        if status == WifiStatus.OFF:
            return cls._asset("icon-wifi-locked.tga")
        elif status == WifiStatus.BAD:
            return cls._asset("icon-wifi-signal-01.tga")
        elif status == WifiStatus.OKAY:
            return cls._asset("icon-wifi-signal-02.tga")
        elif status == WifiStatus.GOOD:
            return cls._asset("icon-wifi-signal-03.tga")
        elif status == WifiStatus.GREAT:
            return cls._asset("icon-wifi-signal-04.tga")
        else:
            return cls._asset("icon-wifi-locked.tga")

    @classmethod
    def get_volume_indicator(cls, volume):
        return cls._asset(f"icon-volume-{volume:02d}.tga")


    @classmethod
    def _grid_multi_row_selected_bg(cls):
        return cls._asset("bg-game-item-f.tga")
    
    @classmethod
    def _grid_multi_row_unselected_bg(cls):
        return cls._asset("bg-game-item-n.tga")

    @classmethod
    def _grid_single_row_selected_bg(cls):
        return cls._asset("bg-game-item-single-f.tga")

    @classmethod
    def get_grid_game_selected_bg(cls):
        return cls._asset("grid-game-selected.tga")

    @classmethod
    def get_system_icon(cls, system):
        if(cls._daijisho_theme_index is not None):
            return cls._daijisho_theme_index.get_file_name_for_system(system)
        else:
            return cls._icon(system + ".tga")

    @classmethod
    def get_default_system_icon(cls):
        if(cls._daijisho_theme_index is not None):
            return cls._daijisho_theme_index.get_default_filename()
        else:
            return None   

    @classmethod
    def get_system_icon_selected(cls, system):
        if(cls._daijisho_theme_index is not None):
            return cls._daijisho_theme_index.get_file_name_for_system(system)
        else:
            return cls._icon("sel",system + ".tga")

    @classmethod
    def get_font(cls, font_purpose : FontPurpose):
        try:
            match font_purpose:
                case FontPurpose.TOP_BAR_TEXT:
                    font = os.path.join(cls._path,cls._data["list"]["font"]) 
                case FontPurpose.BATTERY_PERCENT:
                    font = os.path.join(cls._path,cls._data["list"]["font"]) 
                case FontPurpose.ON_SCREEN_KEYBOARD:
                    font = os.path.join(cls._path,cls._data["list"]["font"]) 
                case FontPurpose.GRID_ONE_ROW:
                    font = os.path.join(cls._path,cls._data["grid"]["font"]) 
                case FontPurpose.GRID_MULTI_ROW:
                    font = os.path.join(cls._path,cls._data["grid"]["font"]) 
                case FontPurpose.LIST:
                    font = os.path.join(cls._path,cls._data["list"]["font"]) 
                case FontPurpose.DESCRIPTIVE_LIST_TITLE:
                    font = os.path.join(cls._path,cls._data["list"]["font"]) 
                case FontPurpose.MESSAGE:
                    font = os.path.join(cls._path,cls._data["list"]["font"]) 
                case FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION:
                    font = os.path.join(cls._path,cls._data["list"]["font"]) 
                case FontPurpose.SHADOWED:
                    font = os.path.join(cls._path,cls._data["shadowed"]["font"]) 
                case FontPurpose.SHADOWED_BACKDROP:
                    font = os.path.join(cls._path,cls._data["shadowed"]["font"]) 
                case FontPurpose.SHADOWED_SMALL:
                    font = os.path.join(cls._path,cls._data["shadowed"]["font"]) 
                case FontPurpose.SHADOWED_BACKDROP_SMALL:
                    font = os.path.join(cls._path,cls._data["shadowed"]["font"]) 
                case _:
                    font = os.path.join(cls._path,cls._data["list"]["font"]) 
                
            if os.path.exists(font):
                return font 
            else:
                return Theme.get_fallback_font()
        except Exception as e:
            PyUiLogger.get_logger().warning(f"No font specified for {font_purpose} or error loading it {e}. Using fallback font.")
            return Theme.get_fallback_font()

    @classmethod
    def get_fallback_font(cls):
        base_dir = os.path.abspath(sys.path[0])
        return os.path.join(base_dir, "themes", "font.ttf")

    @classmethod
    def get_font_size(cls, font_purpose : FontPurpose):
        try:
            match font_purpose:
                case FontPurpose.TOP_BAR_TEXT:
                    return cls._data.get("topBarFontSize", cls._data["list"].get("size", 24))
                case FontPurpose.BATTERY_PERCENT:
                    return cls._data.get("batteryPercentFontSize", cls._data["list"].get("size", 24))
                case FontPurpose.ON_SCREEN_KEYBOARD:
                    return cls._data["list"].get("size", 24)
                case FontPurpose.GRID_ONE_ROW:
                    return cls._data.get("gridSingleRowFontSize", cls._data["grid"].get("grid1x4", cls._data["grid"].get("size",25)))
                case FontPurpose.GRID_MULTI_ROW:
                    return cls._data.get("gridMultiRowFontSize", cls._data["grid"].get("grid3x4", cls._data["grid"].get("size",18)))
                case FontPurpose.LIST:
                    return cls._data.get("listFontSize",cls._data["list"].get("size", 24))
                case FontPurpose.DESCRIPTIVE_LIST_TITLE:
                    return cls._data.get("descListFontSize",cls._data["list"].get("size", 24))
                case FontPurpose.MESSAGE:
                    return cls._data.get("messageFontSize",cls._data["list"].get("size", 24))
                case FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION:
                    return cls._data.get("descriptionFontSize",cls._data["grid"].get("grid3x4", cls._data["grid"].get("size",18)))
                case FontPurpose.LIST_INDEX:
                    return cls._data.get("indexSelectedFontSize",cls._data["list"].get("size", 20))
                case FontPurpose.LIST_TOTAL:
                    return cls._data.get("indexTotalSize",cls._data["list"].get("size", 20))
                case FontPurpose.SHADOWED:
                    try:
                        return cls._data["shadowed"]["shadowedFontSize"] 
                    except Exception as e:
                        #PyUiLogger.get_logger().warning(f"Theme is missing [\"shadowed\"][\"shadowedFontSize\"] ")
                        return int(40 * cls._default_multiplier)
                case FontPurpose.SHADOWED_BACKDROP:
                    try:
                        return cls._data["shadowed"]["shadowedFontBackdropSize"]
                    except Exception as e:
                        #PyUiLogger.get_logger().warning(f"Theme is missing [\"shadowed\"][\"shadowedFontBackdropSize\"] ")
                        return int(40 * cls._default_multiplier)
                case FontPurpose.SHADOWED_SMALL:
                    try:
                        return cls._data["shadowed"]["shadowedFontSmallSize"] 
                    except Exception as e:
                        #PyUiLogger.get_logger().warning(f"Theme is missing [\"shadowed\"][\"shadowedFontSmallSize\"] ")
                        return int(26 * cls._default_multiplier)
                case FontPurpose.SHADOWED_BACKDROP_SMALL:
                    try:
                        return cls._data["shadowed"]["shadowedFontBackdropSmallSize"]
                    except Exception as e:
                        #PyUiLogger.get_logger().warning(f"Theme is missing [\"shadowed\"][\"shadowedFontBackdropSmallSize\"] ")
                        return int(26 * cls._default_multiplier)
                case _:
                    return cls._data["list"]["font"]
        except Exception as e:
            PyUiLogger.get_logger().warning(f"No font specified for {font_purpose} or error loading it {e}. Using fallback value of 20.")
            return 20


    @classmethod
    def set_font_size(cls, font_purpose: FontPurpose, size):
        PyUiLogger.get_logger().debug(f"set_font_size: {font_purpose} {size}")
        try:
            match font_purpose:
                case FontPurpose.TOP_BAR_TEXT:
                    cls._data["topBarFontSize"] = size
                case FontPurpose.BATTERY_PERCENT:
                    cls._data["batteryPercentFontSize"] = size
                case FontPurpose.ON_SCREEN_KEYBOARD:
                    pass
                case FontPurpose.GRID_ONE_ROW:
                    cls._data["gridSingleRowFontSize"] = size
                case FontPurpose.GRID_MULTI_ROW:
                    cls._data["gridMultiRowFontSize"] = size
                case FontPurpose.LIST:
                    cls._data["listFontSize"] = size
                case FontPurpose.DESCRIPTIVE_LIST_TITLE:
                    cls._data["descListFontSize"] = size
                case FontPurpose.MESSAGE:
                    cls._data["messageFontSize"] = size
                case FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION:
                    cls._data["descriptionFontSize"] = size
                case FontPurpose.LIST_INDEX:
                    cls._data["indexSelectedFontSize"] = size
                case FontPurpose.LIST_TOTAL:
                    cls._data["indexTotalSize"] = size
                case FontPurpose.SHADOWED:
                    cls._data["indexSelectedFontSize"] = size
                case FontPurpose.SHADOWED_BACKDROP:
                    cls._data["indexTotalSize"] = size
                case FontPurpose.SHADOWED:
                    cls._data["shadowed"]["shadowedFontSize"] = size
                case FontPurpose.SHADOWED_BACKDROP:
                    cls._data["shadowed"]["shadowedFontBackdropSize"]  = size
                case FontPurpose.SHADOWED_SMALL:
                    cls._data["shadowed"]["shadowedFontSmallSize"] = size
                case FontPurpose.SHADOWED_BACKDROP_SMALL:
                    cls._data["shadowed"]["shadowedFontBackdropSmallSize"]  = size
                case _:
                    PyUiLogger.get_logger().error(
                        f"set_font_size: Unknown font purpose {font_purpose}")
                
            cls.save_changes()
        except Exception as e:
            PyUiLogger.get_logger().error(f"set_font_size error occurred: {e}")


    @classmethod
    def text_color(cls, font_purpose : FontPurpose):
        try:
            match font_purpose:
                case FontPurpose.TOP_BAR_TEXT:
                    if(cls._data.get("title") and cls._data["title"]["color"]):
                        return cls.hex_to_color(cls._data["title"]["color"])
                    else:
                        return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.BATTERY_PERCENT:
                    if(cls._data.get("batteryPercentage") and cls._data["batteryPercentage"]["color"]):
                        return cls.hex_to_color(cls._data["batteryPercentage"]["color"])
                    else:
                        return cls.text_color(FontPurpose.TOP_BAR_TEXT)
                case FontPurpose.ON_SCREEN_KEYBOARD:
                    return cls.hex_to_color(cls._data["grid"]["color"])
                case FontPurpose.GRID_ONE_ROW:
                    return cls.hex_to_color(cls._data["grid"]["color"])
                case FontPurpose.GRID_MULTI_ROW:
                    return cls.hex_to_color(cls._data["grid"]["color"])
                case FontPurpose.LIST | FontPurpose.DESCRIPTIVE_LIST_TITLE | FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION:
                    if(cls._data.get("list") and cls._data.get("list").get("color")):
                        return cls.hex_to_color(cls._data.get("list").get("color"))
                    else:
                        return cls.hex_to_color(cls._data["grid"]["color"])
                case FontPurpose.MESSAGE:
                    return cls.hex_to_color(cls._data["grid"]["color"])
                case FontPurpose.LIST_INDEX:
                    return cls.hex_to_color(cls._data["currentpage"]["color"])
                case FontPurpose.LIST_TOTAL:
                    return cls.hex_to_color(cls._data["total"]["color"])
                case FontPurpose.SHADOWED:
                    try:
                        return cls.hex_to_color(cls._data["shadowed"]["shadowedFontColor"])
                    except Exception as e:
                        #PyUiLogger.get_logger().warning(f"Theme is missing [\"shadowedFontColor\"][\"shadowedFontSmallSize\"] ")
                        return cls.hex_to_color("#FFFFFF")
                case FontPurpose.SHADOWED_BACKDROP:
                    try:
                        return cls.hex_to_color(cls._data["shadowed"]["shadowedFontBackdropColor"])
                    except Exception as e:
                        #PyUiLogger.get_logger().warning(f"Theme is missing [\"shadowedFontColor\"][\"shadowedFontBackdropColor\"] ")
                        return cls.hex_to_color("#000000")
                case FontPurpose.SHADOWED_SMALL:
                    try:
                        return cls.hex_to_color(cls._data["shadowed"]["shadowedFontSmallColor"])
                    except Exception as e:
                        #PyUiLogger.get_logger().warning(f"Theme is missing [\"shadowedFontColor\"][\"shadowedFontSmallColor\"] ")
                        return cls.hex_to_color("#FFFFFF")
                case FontPurpose.SHADOWED_BACKDROP_SMALL:
                    try:
                        return cls.hex_to_color(cls._data["shadowed"]["shadowedFontBackdropSmallColor"])
                    except Exception as e:
                        #PyUiLogger.get_logger().warning(f"Theme is missing [\"shadowedFontColor\"][\"shadowedFontBackdropSmallColor\"] ")
                        return cls.hex_to_color("#000000")
                case _:
                    return cls.hex_to_color(cls._data["grid"]["color"])
        except Exception as e:
            PyUiLogger.get_logger().error(f"text_color error occurred: {e}")
            return cls.hex_to_color("#808080")
            
    @classmethod
    def text_color_selected(cls, font_purpose : FontPurpose):
        try:
            match font_purpose:
                case FontPurpose.GRID_ONE_ROW:
                    return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.GRID_MULTI_ROW:
                    return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.LIST | FontPurpose.DESCRIPTIVE_LIST_TITLE | FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION:
                    if(cls._data.get("list") and cls._data.get("list").get("selectedcolor")):
                        return cls.hex_to_color(cls._data.get("list").get("selectedcolor"))
                    else:
                        return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.MESSAGE:
                    return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.LIST_INDEX:
                    return cls.hex_to_color(cls._data["currentpage"]["color"])
                case FontPurpose.LIST_TOTAL:
                    return cls.hex_to_color(cls._data["total"]["color"])
                case FontPurpose.ON_SCREEN_KEYBOARD:
                    return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.SHADOWED:
                    return cls.hex_to_color(cls._data["shadowed"]["shadowedFontColor"])
                case FontPurpose.SHADOWED_BACKDROP:
                    return cls.hex_to_color(cls._data["shadowed"]["shadowedFontBackdropColor"])
                case FontPurpose.SHADOWED:
                    return cls.hex_to_color(cls._data["shadowed"]["shadowedFontSmallColor"])
                case FontPurpose.SHADOWED_BACKDROP:
                    return cls.hex_to_color(cls._data["shadowed"]["shadowedFontBackdropSmallColor"])
                case _:
                    return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
        except Exception as e:
            PyUiLogger.get_logger().error(f"text_color error occurred: {e}")
            return cls.text_color(font_purpose)

    @classmethod
    def hex_to_color(cls,hex_string):
        hex_string = hex_string.lstrip('#')
        if len(hex_string) != 6:
            raise ValueError("Hex string must be in the format '#RRGGBB'")
        R = int(hex_string[0:2], 16)
        G = int(hex_string[2:4], 16)
        B = int(hex_string[4:6], 16)
        return (R, G, B)

    @classmethod
    def get_descriptive_list_icon_offset_x(cls):
        return cls._data.get("descriptiveListIconOffsetX", 10)

    @classmethod
    def get_descriptive_list_icon_offset_y(cls):
        return cls._data.get("descriptiveListIconOffsetY", 10)

    @classmethod
    def get_descriptive_list_text_offset_y(cls):
        return cls._data.get("descriptiveListTextOffsetY", 15)

    @classmethod
    def get_descriptive_list_text_from_icon_offset(cls):
        return cls._data.get("descriptiveListTextFromIconOffset", 10)

    @classmethod
    def get_grid_multirow_text_offset_y_percent(cls):
        return cls._data.get("gridMultirowTextOffsetYPercent", -15)

    @classmethod
    def get_system_select_show_sel_bg_grid_mode(cls):
        return cls._data.get("systemSelectShowSelectedBgGridMode", True)
    
    @classmethod
    def set_system_select_show_sel_bg_grid_mode(cls, value):
        cls._data["systemSelectShowSelectedBgGridMode"] = value
        cls.save_changes()

    @classmethod
    def get_system_select_show_text_grid_mode(cls):
        return cls._data.get("systemSelectShowTextGridMode", True)
    
    @classmethod
    def set_system_select_show_text_grid_mode(cls, value):
        cls._data["systemSelectShowTextGridMode"] = value
        cls.save_changes()

    @classmethod
    def get_game_select_show_text_grid_mode(cls):
        return cls._data.get("gameSelectShowTextGridMode", False)
    
    @classmethod
    def set_game_select_show_text_grid_mode(cls, value):
        cls._data["gameSelectShowTextGridMode"] = value
        cls.save_changes()


    @classmethod
    def get_game_select_show_sel_bg_grid_mode(cls):
        return cls._data.get("gameSelectShowSelectedBgGridMode", True)
    
    @classmethod
    def set_game_select_show_sel_bg_grid_mode(cls, value):
        cls._data["gameSelectShowSelectedBgGridMode"] = value
        cls.save_changes()

    @classmethod
    def get_main_menu_show_text_grid_mode(cls):
        return cls._data.get("mainMenuShowTextGridMode", True)
    
    @classmethod
    def set_main_menu_show_text_grid_mode(cls, value):
        cls._data["mainMenuShowTextGridMode"] = value
        cls.save_changes()

    @classmethod
    def get_grid_bg(cls, rows, cols, use_multi_row_select_as_backup = False):
        # TODO better handle this dynamically
        if rows > 1:
            return cls._grid_multi_row_selected_bg()
        else:
            single_row_bg = cls._grid_single_row_selected_bg()
            if single_row_bg and os.path.exists(single_row_bg):
                return single_row_bg
            elif use_multi_row_select_as_backup:
                return cls._grid_multi_row_selected_bg()
            else:
                return None
                        
    @classmethod
    def get_grid_bg_unselected(cls, rows, cols, use_multi_row_select_as_backup = False):
        # TODO better handle this dynamically
        if rows > 1:
            return cls._grid_multi_row_unselected_bg()
        else:
            #TODO?
            return None

    @classmethod
    def get_view_type_for_main_menu(cls):
        view_type_str = cls._data.get("mainMenuViewType", "GRID_VIEW")
        return getattr(ViewType, view_type_str, ViewType.GRID)

    @classmethod
    def set_view_type_for_main_menu(cls, view_type):
        cls._data["mainMenuViewType"] = view_type.name
        cls.save_changes()

    @classmethod
    def get_view_type_for_system_select_menu(cls):
        view_type_str = cls._data.get("systemSelectViewType", "GRID_VIEW")
        return getattr(ViewType, view_type_str, ViewType.GRID)

    @classmethod
    def set_view_type_for_system_select_menu(cls, view_type):
        cls._data["systemSelectViewType"] = view_type.name
        cls.save_changes()

    @classmethod
    def get_grid_game_selected_resize_type(cls):
        view_type_str = cls._data.get("gameSelectGridResizeType", "ZOOM")
        return getattr(ResizeType, view_type_str, ResizeType.ZOOM)

    @classmethod
    def set_grid_game_selected_resize_type(cls, view_type):
        cls._data["gameSelectGridResizeType"] = view_type.name
        cls.save_changes()

    @classmethod
    def get_grid_game_img_y_offset(cls):
        return cls._data.get("gridGameImageYOffset", 0)

    @classmethod
    def set_grid_game_img_y_offset(cls, value):
        cls._data["gridGameImageYOffset"] = value
        cls.save_changes()

    @classmethod
    def get_view_type_for_app_menu(cls):
        view_type_str = cls._data.get("appMenuViewType", "DESCRIPTIVE_LIST_VIEW")
        return getattr(ViewType, view_type_str, ViewType.ICON_AND_DESC)

    @classmethod
    def get_game_system_select_col_count(cls):
        return cls._data.get("gameSystemSelectColCount", 4)

    @classmethod
    def get_game_system_select_row_count(cls):
        return cls._data.get("gameSystemSelectRowCount", 2)

    @classmethod
    def set_game_system_select_col_count(cls, count):
        cls._data["gameSystemSelectColCount"] = count
        cls.save_changes()

    @classmethod
    def set_game_system_select_row_count(cls, count):
        cls._data["gameSystemSelectRowCount"] = count
        cls.save_changes()
    
    @classmethod
    def pop_menu_x_offset(cls):
        return cls._data.get("popupMenuXOffsetPercent", 0) / 100

    @classmethod
    def pop_menu_y_offset(cls):
        return cls._data.get("popupMenuYOffsetPercent", 0) / 100

    @classmethod
    def pop_menu_add_top_bar_height_to_y_offset(cls):
        return cls._data.get("addTopBarHeightToYOffset", True)

    @classmethod
    def pop_menu_text_padding(cls):
        return cls._data.get("popupMenuTextPad", 20)

    @classmethod
    def popup_menu_cols(cls):
        return cls._data.get("popupMenuCols", 4)

    @classmethod
    def popup_menu_rows(cls):
        return cls._data.get("popupMenuRows", 1)

    @classmethod
    def text_and_image_list_view_mode(cls):
        return cls._data.get("textAndImageListViewMode", "TEXT_LEFT_IMAGE_RIGHT")

    @classmethod
    def scroll_rom_selection_text(cls):
        return cls._data.get("scrollRomSelectionText", True)

    @classmethod
    def show_index_text(cls):
        return cls._data.get("showIndexText", True)

    @classmethod
    def get_game_selection_view_type(cls):
        view_type_str = cls._data.get("gameSelectionViewType", "TEXT_AND_IMAGE")
        return getattr(ViewType, view_type_str, ViewType.TEXT_AND_IMAGE)

    @classmethod
    def set_game_selection_view_type(cls, view_type):
        cls._data["gameSelectionViewType"] = view_type.name
        cls.save_changes()

    @classmethod
    def get_main_menu_column_count(cls):
        return cls._data.get("mainMenuColCount", 4)

    @classmethod
    def set_main_menu_column_count(cls, count):
        cls._data["mainMenuColCount"] = count
        cls.save_changes()

    @classmethod
    def get_recents_enabled(cls):
        return cls._data.get("recentsEnabled", True)

    @classmethod
    def set_recents_enabled(cls, value):
        cls._data["recentsEnabled"] = value
        cls.save_changes()

    @classmethod
    def get_collections_enabled(cls):
        return cls._data.get("collectionsEnabled", False)

    @classmethod
    def set_collections_enabled(cls, value):
        cls._data["collectionsEnabled"] = value
        cls.save_changes()

    @classmethod
    def get_favorites_enabled(cls):
        return cls._data.get("favoritesEnabled", True)

    @classmethod
    def set_favorites_enabled(cls, value):
        cls._data["favoritesEnabled"] = value
        cls.save_changes()
    
    @classmethod
    def get_apps_enabled(cls):
        return cls._data.get("appsEnabled", True)

    @classmethod
    def set_apps_enabled(cls, value):
        cls._data["appsEnabled"] = value
        cls.save_changes()

    @classmethod
    def get_settings_enabled(cls):
        return cls._data.get("settingsEnabled", True)

    @classmethod
    def set_settings_enabled(cls, value):
        cls._data["settingsEnabled"] = value
        cls.save_changes()

    @classmethod
    def get_main_menu_option_ordering(cls):
        return cls._data.get("mainMenuOrdering", ["Recent", "Favorite","Collection", "Game", "App", "Setting"])

    @classmethod
    def get_game_select_row_count(cls):
        return cls._data.get("gameSelectRowCount", 2)

    @classmethod
    def set_game_select_row_count(cls, value):
        cls._data["gameSelectRowCount"] = value
        cls.save_changes()

    @classmethod
    def get_game_select_col_count(cls):
        return cls._data.get("gameSelectColCount", 4)

    @classmethod
    def set_game_select_col_count(cls, value):
        cls._data["gameSelectColCount"] = value
        cls.save_changes()

    @classmethod
    def get_game_select_img_width(cls):
        from devices.device import Device
        return cls._data.get("gameSelectImgWidth", int(Device.screen_width() * 294 / 640))
    
    @classmethod
    def set_game_select_img_width(cls, value):
        cls._data["gameSelectImgWidth"] = value
        cls.save_changes()

    @classmethod
    def get_grid_game_select_img_width(cls):
        from devices.device import Device
        return cls._data.get("gridGameSelectImgWidth", int(Device.screen_width() * 140 / 640))
    
    @classmethod
    def set_grid_game_select_img_width(cls, value):
        cls._data["gridGameSelectImgWidth"] = value
        cls.save_changes()

    @classmethod
    def get_list_game_select_img_width(cls):
        return cls._data.get("listGameSelectImgWidth", cls.get_game_select_img_width())
    
    @classmethod
    def set_list_game_select_img_width(cls, value):
        cls._data["listGameSelectImgWidth"] = value
        cls.save_changes()

    @classmethod
    def get_carousel_game_select_primary_img_width(cls):
        return cls._data.get("carouselGameSelectPrimaryImgWidth", 40)
    
    @classmethod
    def set_carousel_game_select_primary_img_width(cls, value):
        cls._data["carouselGameSelectPrimaryImgWidth"] = value
        cls.save_changes()

    @classmethod
    def get_carousel_game_select_shrink_further_away(cls):
        return cls._data.get("carouselGameSelectShrinkFurtherAway", False)
    
    @classmethod
    def set_carousel_game_select_shrink_further_away(cls, value):
        cls._data["carouselGameSelectShrinkFurtherAway"] = value
        cls.save_changes()

    @classmethod
    def get_carousel_game_select_sides_hang_off(cls):
        return cls._data.get("carouselGameSelectSidesHangOff", True)

    @classmethod
    def set_carousel_game_select_sides_hang_off(cls, value):
        cls._data["carouselGameSelectSidesHangOff"] = value
        cls.save_changes()    

    @classmethod
    def get_game_select_img_height(cls):
        from devices.device import Device
        return cls._data.get("gameSelectImgHeight", int(Device.screen_height() * 300 / 640))
    
    @classmethod
    def set_game_select_img_height(cls, value):
        cls._data["gameSelectImgHeight"] = value
        cls.save_changes()

    @classmethod
    def get_grid_game_select_img_height(cls):
        from devices.device import Device
        return cls._data.get("gridGameSelectImgHeight", int(Device.screen_width() * 140 / 640))
    
    @classmethod
    def set_grid_game_select_img_height(cls, value):
        cls._data["grid_gameSelectImgHeight"] = value
        cls.save_changes()

    @classmethod
    def get_list_game_select_img_height(cls):
        return cls._data.get("listGameSelectImgHeight", cls.get_game_select_img_height())
    
    @classmethod
    def set_list_game_select_img_height(cls, value):
        cls._data["listGameSelectImgHeight"] = value
        cls.save_changes()

    @classmethod
    def get_set_top_bar_text_to_game_selection(cls):
        return cls._data.get("setTopBarTextToGameSelection", False)
    
    @classmethod
    def set_set_top_bar_text_to_game_selection(cls, value):
        cls._data["setTopBarTextToGameSelection"] = value
        cls.save_changes()

    @classmethod
    def skip_main_menu(cls):
        return cls._data.get("skipMainMenu", False)
    
    @classmethod
    def set_skip_main_menu(cls, value):
        cls._data["skipMainMenu"] = value
        cls.save_changes()

    @classmethod
    def get_grid_multi_row_sel_bg_resize_pad_width(cls):
        return cls._data.get("gridMultiRowSelBgResizePadWidth", 20)
    
    @classmethod
    def set_grid_multi_row_sel_bg_resize_pad_width(cls, value):
        cls._data["gridMultiRowSelBgResizePadWidth"] = value
        cls.save_changes()

    @classmethod
    def get_grid_multi_row_sel_bg_resize_pad_height(cls):
        return cls._data.get("gridMultiRowSelBgResizePadHeight", 20)
    
    @classmethod
    def set_grid_multi_row_sel_bg_resize_pad_height(cls, value):
        cls._data["gridMultiRowSelBgResizePadHeight"] = value
        cls.save_changes()

    @classmethod
    def get_top_bar_initial_x_offset(cls):
        return cls._data.get("topBarInitialXOffset", 20)

    @classmethod
    def set_top_bar_initial_x_offset(cls, value):
        cls._data["topBarInitialXOffset"] = value
        cls.save_changes()
    
    @classmethod
    def get_system_select_grid_img_y_offset(cls, text_height):
        default_height = -25
        if(0 != text_height):
            default_height = -1 * text_height        

        return cls._data.get("systemSelectGridImageYOffset", default_height)

    @classmethod
    def get_app_icon(cls, app_name):
        return cls._icon("app",app_name)

    @classmethod
    def include_index_text(cls):
        return cls._data.get("includeIndexText", True)

    @classmethod
    def get_view_type_for_game_switcher(cls):
        view_type_str = cls._data.get("gameSwitcherViewType", "FULLSCREEN_GRID")
        return getattr(ViewType, view_type_str, ViewType.FULLSCREEN_GRID)

    @classmethod
    def set_view_type_for_game_switcher(cls, view_type):
        cls._data["gameSwitcherViewType"] = view_type.name
        cls.save_changes()

    @classmethod
    def get_resize_type_for_game_switcher(cls):
        view_type_str = cls._data.get("gameSwitcherResizeType", "FIT")
        return getattr(ResizeType, view_type_str, ResizeType.FIT)

    @classmethod
    def set_resize_type_for_game_switcher(cls, resize_type):
        cls._data["gameSwitcherResizeType"] = resize_type.name
        cls.save_changes()

    @classmethod
    def get_full_screen_grid_game_menu_resize_type(cls):
        view_type_str = cls._data.get("fullScreenGridGameMenuResizeType", "ZOOM")
        return getattr(ResizeType, view_type_str, ResizeType.ZOOM)

    @classmethod
    def set_full_screen_grid_game_menu_resize_type(cls, resize_type):
        cls._data["fullScreenGridGameMenuResizeType"] = resize_type.name
        cls.save_changes()

    @classmethod
    def get_set_top_bar_text_to_game_selection_for_game_switcher(cls):
        return cls._data.get("gameSwitcherSetTopBarTextToGameSelection", True)
    
    @classmethod
    def set_set_top_bar_text_to_game_selection_for_game_switcher(cls, value):
        cls._data["gameSwitcherSetTopBarTextToGameSelection"] = value
        cls.save_changes()
