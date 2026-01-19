import json
import os
from pathlib import Path
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
from utils.py_ui_config import PyUiConfig
from views.view_type import ViewType

class Theme():
    _data = {}
    _path = ""
    _skin_folder = ""
    _bg_folder = ""
    _icon_folder = ""
    _loaded_file_path = ""
    _daijisho_theme_index = None
    _button_press_wav = None
    _default_multiplier = 1.0
    _play_button_press_sounds = True
    _asset_cache = {}  # shared cache for asset + icon lookups
    _grid_game_default_size = 140

    @classmethod
    def init(cls, path, width, height):
        cls.set_theme_path(path, width, height)

    @classmethod
    def set_theme_path(cls,path, width = 0, height = 0):
        #Uneeded due to moving where we convert?
        #cls.load_defaults_so_user_can_see_at_least(path)
        cls._path = path
        resolution_specific_config = f"config_{width}x{height}.json"
        config_path = os.path.join(path, resolution_specific_config)
        if not os.path.exists(config_path):
            config_path = "config.json"
            cls._skin_folder = cls._get_asset_folder(cls._path, "skin", -1, -1)
            cls._icon_folder = cls._get_asset_folder(cls._path, "icons", -1, -1)
            cls._bg_folder = cls._get_asset_folder(cls._path, "bg", -1, -1)
        else:
            cls._skin_folder = cls._get_asset_folder(cls._path, "skin", width, height)
            cls._icon_folder = cls._get_asset_folder(cls._path, "icons", width, height)
            cls._bg_folder = cls._get_asset_folder(cls._path, "bg", width, height)


        cls._data.clear()
        cls._load_defaults()
        cls._load_from_file(os.path.join(path, config_path))

        daijisho_theme_index_file = os.path.join(cls._path, cls._icon_folder,"index.json")
        if os.path.exists(daijisho_theme_index_file):
            try:
                cls._daijisho_theme_index = DaijishoThemeIndex(daijisho_theme_index_file)
                #PyUiLogger.get_logger().info(f"Using DaijishoThemeIndex from {daijisho_theme_index_file}")
            except Exception:
                PyUiLogger.get_logger().exception(f"Failed to load DaijishoThemeIndex from {daijisho_theme_index_file}")
                cls._daijisho_theme_index = None
        else:
            cls._daijisho_theme_index = None
            #PyUiLogger.get_logger().info(f"Using Miyoo style theme")

        scale_width = Device.get_device().screen_width() / 640
        scale_height = Device.get_device().screen_height() / 480

        if(scale_width > scale_height):
            cls.width_multiplier = ((scale_width-scale_height) / scale_height) + 1
            cls.height_multiplier = 1.0
        else:
            cls.height_multiplier = ((scale_height-scale_width) / scale_width) + 1
            cls.width_multiplier = 1.0

        cls._default_multiplier = min(scale_width, scale_height)

        cls.button_press_sounds_changed()
        cls.bgm_setting_changed()


    @classmethod
    def bgm_setting_changed(cls):
        Device.get_device().get_audio_system().audio_stop_loop()
        if(Device.get_device().get_system_config().play_bgm()):
            bgm_wav = os.path.join(cls._path, "sound", "bgm.wav")
            bgm_mp3 = os.path.join(cls._path, "sound", "bgm.mp3")
            Device.get_device().get_audio_system().audio_set_volume(Device.get_device().get_system_config().bgm_volume())
            if os.path.exists(bgm_wav) and os.path.getsize(bgm_wav) > 0:
                Device.get_device().get_audio_system().audio_loop_wav(bgm_wav)
            elif os.path.exists(bgm_mp3) and os.path.getsize(bgm_mp3) > 0:
                Device.get_device().get_audio_system().audio_loop_mp3(bgm_mp3)

    @classmethod
    def button_press_sounds_changed(cls):
        cls._play_button_press_sounds = Device.get_device().get_system_config().play_button_press_sound()
        button_press_wav = os.path.join(cls._path, "sound", "change.wav")
        if(os.path.exists(button_press_wav)) and os.path.getsize(button_press_wav) > 0:
            cls._button_press_wav = button_press_wav
            Device.get_device().get_audio_system().load_wav(button_press_wav)

    @classmethod
    def controller_button_pressed(cls, input):
        if(cls._play_button_press_sounds and cls._button_press_wav is not None):
            Device.get_device().get_audio_system().audio_play_wav(cls._button_press_wav)

    @classmethod
    def convert_theme_if_needed(cls, path, width, height):
        resolution_specific_config = f"config_{width}x{height}.json"
        config_path = os.path.join(path, resolution_specific_config)

        resolution_converted = False
        if os.path.exists(config_path):
            #PyUiLogger.get_logger().info(f"Resolution specific config found, using {resolution_specific_config}")
            pass #don't need to log
        elif ThemePatcher.patch_theme(path,width, height) and os.path.exists(config_path):
            resolution_converted = True

        #qoi_converted = ThemePatcher.convert_to_qoi(path)

        if(resolution_converted): # or qoi_converted):
            Device.get_device().exit_pyui()

    @classmethod
    def load_defaults_so_user_can_see_at_least(cls, path):
        cls._data.clear()
        cls._path = path
        cls._load_defaults()

        cls._load_from_file(os.path.join(path, "config.json"))

        cls._path = path
        cls._skin_folder = cls._get_asset_folder(cls._path,"skin", -1, -1)
        cls._icon_folder = cls._get_asset_folder(cls._path,"icons", -1, -1)

    @classmethod
    def get_theme_path(cls):
        return cls._path

    @classmethod
    def _get_asset_folder(cls, path, base_folder, width, height):
        folder = f"{base_folder}_{width}x{height}"
        full_path = os.path.join(path, folder)
        if os.path.isdir(full_path):
            #PyUiLogger.get_logger().info(f"Resolution specific assets found, using {folder}")
            return folder
        else:
            #PyUiLogger.get_logger().info(f"No resolution specific assets {folder} found, using {base_folder}")
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
        except Exception as e:
            PyUiLogger.get_logger().error(
                f"Unexpected error while loading {file_path}: {e}\n{traceback.format_exc()}"
            )
            Device.get_device().get_system_config().delete_theme_entry()
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
    def _resolve_png_path(cls, base_folder, parts):
        path = os.path.join(cls._path, base_folder, *parts)

        if path.endswith(".qoi"):
            png_path = path[:-4] + ".png"
            return png_path

        return path
        
    @classmethod
    def _resolve_file(cls, base_folder, parts, cache_missing=True):
        """
        Shared resolver:
        - Checks full path
        - If missing and ends in .qoi, tries .png 
        - Caches results
        """
        key = (base_folder, parts)
        if key in cls._asset_cache:
            return cls._asset_cache[key]

        path = os.path.join(cls._path, base_folder, *parts)

        # Direct hit
        if os.path.exists(path):
            cls._asset_cache[key] = path
            return path

        # Fallback only makes sense for .qoi assets/icons
        if path.endswith(".qoi"):
            png_path = path[:-4] + ".png"
            if os.path.exists(png_path):
                cls._asset_cache[key] = png_path
                return png_path

        # Nothing found
        if(cache_missing):
            cls._asset_cache[key] = None
        return None

    @classmethod
    def _asset(cls, *parts, cache_missing=True):
        return cls._resolve_file(cls._skin_folder, parts, cache_missing)

    @classmethod
    def _bg(cls, *parts, cache_missing=True):
        return cls._resolve_file(cls._bg_folder, parts, cache_missing)

    @classmethod
    def _icon(cls, *parts):
        return cls._resolve_file(cls._icon_folder, parts)
    
    @classmethod
    def background(cls, page = None):
        if(page is None):
            return cls._asset("background.qoi")
        else:
            background_img = cls._bg(f"{page.lower()}.qoi")
            return background_img

    @classmethod
    def favorite(cls): return cls._asset("ic-favorite-n.qoi")
    
    @classmethod
    def favorite_selected(cls): return cls._asset("ic-favorite-f.qoi")
    
    @classmethod
    def recent(cls): return cls._asset("ic-recent-n.qoi")
    
    @classmethod
    def recent_selected(cls): return cls._asset("ic-recent-f.qoi")

    @classmethod
    def collection(cls): return cls._asset("ic-collection-n.qoi")
    
    @classmethod
    def collection_selected(cls): return cls._asset("ic-collection-f.qoi")
    
    @classmethod
    def game(cls): return cls._asset("ic-game-n.qoi")
    
    @classmethod
    def game_selected(cls): return cls._asset("ic-game-f.qoi")
    
    @classmethod
    def app(cls): return cls._asset("ic-app-n.qoi")
    
    @classmethod
    def app_selected(cls): return cls._asset("ic-app-f.qoi")
    
    @classmethod
    def settings(cls): return cls._asset("ic-setting-n.qoi")
    
    @classmethod
    def settings_selected(cls): return cls._asset("ic-setting-f.qoi")
    
    @classmethod
    def get_title_bar_bg(cls): return cls._asset("bg-title.qoi")
    
    @classmethod
    def bottom_bar_bg(cls): return cls._asset("tips-bar-bg.qoi")
    
    @classmethod
    def confirm_icon(cls): return cls._asset("icon-A-54.qoi")
    
    @classmethod
    def back_icon(cls): return cls._asset("icon-B-54.qoi")
    
    @classmethod
    def start_icon(cls): return cls._asset("icon-START.qoi")
    
    @classmethod
    def show_bottom_bar(cls): return cls._data.get("showBottomBar", True) is not False
    
    @classmethod
    def ignore_top_and_bottom_bar_for_layout(cls): return cls._data.get("ignoreTopAndBottomBarForLayout", False)
    
    @classmethod
    def show_top_bar_text(cls): return cls._data.get("showTopBarText", True)
    
    @classmethod
    def render_top_and_bottom_bar_last(cls): return cls._data.get("renderTopAndBottomBarLast", False)
    
    @classmethod
    def confirm_text(cls): return cls._data.get("confirmText", "Okay")
    
    @classmethod
    def back_text(cls): return cls._data.get("backText", "Back")
    
    @classmethod
    def favorite_icon(cls): return cls._asset("ic-favorite-mark.qoi")
    
    @classmethod
    def get_list_large_selected_bg(cls): return cls._asset("bg-list-l.qoi")
   
    @classmethod
    def menu_popup_bg_large(cls): 
        menu_selected_bg = cls._asset("bg-pop-menu-4.qoi", cache_missing=False)
        if(menu_selected_bg is None):
            cls.create_bg_pop_menu_4()
        return cls._asset("bg-pop-menu-4.qoi")

    @classmethod
    def create_bg_pop_menu_4(cls):  
        #Background isn't the best but its the only one that often doesnt have transparency on the bottom
        input_image = cls._resolve_png_path(cls._skin_folder,["background.png"])
        output_image = cls._resolve_png_path(cls._skin_folder,["bg-pop-menu-4.png"])
        PyUiLogger.get_logger().info(f"Creating resized {output_image} from {input_image}")      
        Device.get_device().get_image_utils().resize_image(input_image,
                                              output_image,
                                              320,
                                              240,
                                              preserve_aspect_ratio=False)
 
    @classmethod
    def keyboard_bg(cls): 
        return cls._asset("bg-grid-s.qoi")
    
    @classmethod
    def keyboard_entry_bg(cls): return cls._asset("bg-list-l.qoi")
    
    @classmethod
    def key_bg(cls): return cls._asset("bg-btn-01-n.qoi")
    
    @classmethod
    def key_selected_bg(cls): return cls._asset("bg-btn-01-f.qoi")
    
    @classmethod
    def get_list_small_selected_bg(cls): return cls._asset("bg-list-s.qoi")
    
    @classmethod
    def create_bg_list_s2(cls):  
        input_image = cls._resolve_png_path(cls._skin_folder,["bg-list-s.png"])
        output_image = cls._resolve_png_path(cls._skin_folder,["bg-list-s2.png"])
        PyUiLogger.get_logger().info(f"Creating resized {output_image} from {input_image}")      
        Device.get_device().get_image_utils().resize_image(input_image,
                                              output_image,
                                              320,
                                              60,
                                              preserve_aspect_ratio=False)

    @classmethod
    def get_popup_menu_selected_bg(cls): 
        menu_selected_bg = cls._asset("bg-list-s2.qoi", cache_missing=False)
        if(menu_selected_bg is None):
            cls.create_bg_list_s2()
        return cls._asset("bg-list-s2.qoi")
    
    @classmethod
    def get_missing_image_path(cls): return cls._asset("missing_image.qoi")
    
    @classmethod
    def get_battery_icon(cls, charging, battery_percent):
        if ChargeStatus.CHARGING == charging:
            if battery_percent > 97:
                return cls._asset("ic-power-charge-100%.qoi")
            elif battery_percent >= 75:
                return cls._asset("ic-power-charge-75%.qoi")
            elif battery_percent >= 50:
                return cls._asset("ic-power-charge-50%.qoi")
            elif battery_percent >= 25:
                return cls._asset("ic-power-charge-25%.qoi")
            else:
                return cls._asset("ic-power-charge-0%.qoi")
        else:
            if battery_percent >= 97:
                return cls._asset("power-full-icon.qoi")
            elif battery_percent >= 80:
                return cls._asset("power-80%-icon.qoi")
            elif battery_percent >= 50:
                return cls._asset("power-50%-icon.qoi")
            elif battery_percent >= 20:
                return cls._asset("power-20%-icon.qoi")
            else:
                return cls._asset("power-0%-icon.qoi")
            
    @classmethod
    def get_wifi_icon(cls, status):
        if status == WifiStatus.OFF:
            return cls._asset("icon-wifi-locked.qoi")
        elif status == WifiStatus.BAD:
            return cls._asset("icon-wifi-signal-01.qoi")
        elif status == WifiStatus.OKAY:
            return cls._asset("icon-wifi-signal-02.qoi")
        elif status == WifiStatus.GOOD:
            return cls._asset("icon-wifi-signal-03.qoi")
        elif status == WifiStatus.GREAT:
            return cls._asset("icon-wifi-signal-04.qoi")
        else:
            return cls._asset("icon-wifi-locked.qoi")

    @classmethod
    def get_volume_indicator(cls, volume):
        return cls._asset(f"icon-volume-{volume:02d}.qoi")


    @classmethod
    def _grid_multi_row_selected_bg(cls):
        return cls._asset("bg-game-item-f.qoi")
    
    @classmethod
    def _grid_multi_row_unselected_bg(cls):
        return cls._asset("bg-game-item-n.qoi")

    @classmethod
    def _grid_single_row_selected_bg(cls):
        return cls._asset("bg-game-item-single-f.qoi")

    @classmethod
    def get_grid_game_selected_bg(cls):
        return cls._asset("grid-game-selected.qoi")

    @classmethod
    def get_grid_system_selected_bg(cls):
        return cls._asset("grid-system-selected.qoi")

    @classmethod
    def get_system_icon(cls, system):
        if(cls._daijisho_theme_index is not None):
            return cls._daijisho_theme_index.get_file_name_for_system(system)
        else:
            return cls._icon(system + ".qoi")

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
            return cls._icon("sel",system + ".qoi")

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
            #PyUiLogger.get_logger().warning(f"No font specified for {font_purpose} or error loading it {e}. Using fallback font.")
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
                    return cls._data.get("topBarFontSize", cls._data["list"].get("size", int(24*cls._default_multiplier)))
                case FontPurpose.BATTERY_PERCENT:
                    return cls._data.get("batteryPercentFontSize", cls._data["list"].get("size", int(24*cls._default_multiplier)))
                case FontPurpose.ON_SCREEN_KEYBOARD:
                    return cls._data["list"].get("size", int(24*cls._default_multiplier))
                case FontPurpose.GRID_ONE_ROW:
                    return cls._data.get("gridSingleRowFontSize", cls._data["grid"].get("grid1x4", cls._data["grid"].get("size",int(25*cls._default_multiplier))))
                case FontPurpose.GRID_MULTI_ROW:
                    return cls._data.get("gridMultiRowFontSize", cls._data["grid"].get("grid3x4", cls._data["grid"].get("size",int(18*cls._default_multiplier))))
                case FontPurpose.LIST:
                    return cls._data.get("listFontSize",cls._data["list"].get("size", int(24*cls._default_multiplier)))
                case FontPurpose.DESCRIPTIVE_LIST_TITLE:
                    return cls._data.get("descListFontSize",cls._data["list"].get("size", int(24*cls._default_multiplier)))
                case FontPurpose.MESSAGE:
                    return cls._data.get("messageFontSize",cls._data["list"].get("size", int(24*cls._default_multiplier)))
                case FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION:
                    return cls._data.get("descriptionFontSize",cls._data["grid"].get("grid3x4", cls._data["grid"].get("size",int(18*cls._default_multiplier))))
                case FontPurpose.LIST_INDEX:
                    return cls._data.get("indexSelectedFontSize",cls._data["list"].get("size", int(20*cls._default_multiplier)))
                case FontPurpose.LIST_TOTAL:
                    return cls._data.get("indexTotalSize",cls._data["list"].get("size", int(20*cls._default_multiplier)))
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
            # PyUiLogger.get_logger().warning(f"No font specified for {font_purpose} or error loading it {e}. Using fallback value of 20.")
            return int(20 * cls._default_multiplier)


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
                        color = cls.hex_to_color(cls._data.get("list").get("selectedcolor"))
                        #PyUiLogger.get_logger().error(f"list selected color is {color}")                        
                        return color
                    else:
                        #PyUiLogger.get_logger().error(f"list selectedcolor not found, using grid")
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
        return cls._data.get("descriptiveListIconOffsetX", int(10*cls._default_multiplier))

    @classmethod
    def get_descriptive_list_icon_offset_y(cls):
        return cls._data.get("descriptiveListIconOffsetY", int(10*cls._default_multiplier))

    @classmethod
    def get_descriptive_list_text_offset_y(cls):
        return cls._data.get("descriptiveListTextOffsetY", int(15*cls._default_multiplier))

    @classmethod
    def get_descriptive_list_text_from_icon_offset(cls):
        return cls._data.get("descriptiveListTextFromIconOffset", int(10*cls._default_multiplier))

    @classmethod
    def get_grid_multirow_text_offset_y_percent(cls):
        return cls._data.get("gridMultirowTextOffsetYPercent", int(-15*cls._default_multiplier))

    @classmethod
    def get_system_select_show_sel_bg_grid_mode(cls):
        return cls._data.get("systemSelectShowSelectedBgGridMode", True)
    
    @classmethod
    def set_system_select_show_sel_bg_grid_mode(cls, value):
        cls._data["systemSelectShowSelectedBgGridMode"] = value
        cls.save_changes()

    @classmethod
    def get_system_selection_set_top_bar_text(cls):
        return cls._data.get("systemSelectionSetTopBarText", False)
    
    @classmethod
    def set_system_selection_set_top_bar_text(cls, value):
        cls._data["systemSelectionSetTopBarText"] = value
        cls.save_changes()

    @classmethod
    def get_system_selection_set_bottom_bar_text(cls):
        return cls._data.get("systemSelectionSetBottomBarText", False)
    
    @classmethod
    def set_system_selection_set_bottom_bar_text(cls, value):
        cls._data["systemSelectionSetBottomBarText"] = value
        cls.save_changes()

    @classmethod
    def get_system_select_show_text_grid_mode(cls):
        return cls._data.get("systemSelectShowTextGridMode", True)
        
    @classmethod
    def set_system_select_show_text_grid_mode(cls, value):
        cls._data["systemSelectShowTextGridMode"] = value
        cls.save_changes()

    @classmethod
    def get_system_select_render_full_screen_grid_text_overlay(cls):
        return cls._data.get("systemSelectFullScreenGridTextOverlay", True)
    
    @classmethod
    def set_system_select_render_full_screen_grid_text_overlay(cls, value):
        cls._data["systemSelectFullScreenGridTextOverlay"] = value
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
    def get_grid_system_selected_resize_type(cls):
        view_type_str = cls._data.get("systemSelectGridResizeType", "NONE")
        return getattr(ResizeType, view_type_str, ResizeType.NONE)

    @classmethod
    def set_grid_system_selected_resize_type(cls, view_type):
        cls._data["systemSelectGridResizeType"] = view_type.name
        cls.save_changes()

    @classmethod
    def get_grid_game_img_y_offset(cls):
        return cls._data.get("gridGameImageYOffset", 0)

    @classmethod
    def set_grid_game_img_y_offset(cls, value):
        cls._data["gridGameImageYOffset"] = value
        cls.save_changes()

    @classmethod
    def get_grid_system_img_y_offset(cls):
        return cls._data.get("gridSystemImageYOffset", 0)

    @classmethod
    def set_grid_system_img_y_offset(cls, value):
        cls._data["gridSystemImageYOffset"] = value
        cls.save_changes()

    @classmethod
    def get_carousel_system_x_pad(cls):
        return cls._data.get("carouselSystemXPad", 0)

    @classmethod
    def set_carousel_system_x_pad(cls, value):
        cls._data["carouselSystemXPad"] = value
        cls.save_changes()

    @classmethod
    def get_carousel_system_additional_y_offset(cls):
        return cls._data.get("carouselSystemAdditionalYOffset", 0)

    @classmethod
    def set_carousel_system_additional_y_offset(cls, value):
        cls._data["carouselSystemAdditionalYOffset"] = value
        cls.save_changes()
        
    @classmethod
    def get_carousel_system_resize_type(cls):
        view_type_str = cls._data.get("carouselSystemResizeType", "FIT")
        return getattr(ResizeType, view_type_str, ResizeType.FIT)

    @classmethod
    def set_carousel_system_resize_type(cls, view_type):
        cls._data["carouselSystemResizeType"] = view_type.name
        cls.save_changes()

    @classmethod
    def get_carousel_system_selected_offset(cls):
        return cls._data.get("carouselSystemSelectedOffset", 0)

    @classmethod
    def set_carousel_system_selected_offset(cls, value):
        cls._data["carouselSystemSelectedOffset"] = value
        cls.save_changes()
        
    @classmethod
    def get_carousel_use_selected_image_in_animation(cls):
        return cls._data.get("carouselSystemUseSelectedImageInAnimation", True)

    @classmethod
    def set_carousel_use_selected_image_in_animation(cls, value):
        cls._data["carouselSystemUseSelectedImageInAnimation"] = value
        cls.save_changes()
        
    @classmethod
    def get_carousel_system_external_x_offset(cls):
        return cls._data.get("carouselSystemExternalXPad", 0)

    @classmethod
    def set_carousel_system_external_x_offset(cls, value):
        cls._data["carouselSystemExternalXPad"] = value
        cls.save_changes()

    @classmethod
    def get_carousel_system_use_percentage_mode(cls):
        return cls._data.get("carouselSystemUsePercentageMode", True)

    @classmethod
    def set_carousel_system_use_percentage_mode(cls, value):
        cls._data["carouselSystemUsePercentageMode"] = value
        cls.save_changes()

    @classmethod
    def get_carousel_system_fixed_width(cls):
        return cls._data.get("carouselSystemFixedWidth", 100)

    @classmethod
    def set_carousel_system_fixed_width(cls, value):
        cls._data["carouselSystemFixedWidth"] = value
        cls.save_changes()

    @classmethod
    def get_carousel_system_fixed_selected_width(cls):
        return cls._data.get("carouselSystemFixedSelectedWidth", cls.get_carousel_system_fixed_width())

    @classmethod
    def set_carousel_system_fixed_selected_width(cls, value):
        cls._data["carouselSystemFixedSelectedWidth"] = value
        cls.save_changes()

    @classmethod
    def get_view_type_for_app_menu(cls):
        view_type_str = cls._data.get("appMenuViewType", "DESCRIPTIVE_LIST_VIEW")
        return getattr(ViewType, view_type_str, ViewType.ICON_AND_DESC)

    @classmethod
    def get_game_system_select_col_count(cls):
        return cls._data.get("gameSystemSelectColCount", int(4 * cls.width_multiplier))

    @classmethod
    def get_game_system_select_row_count(cls):
        return cls._data.get("gameSystemSelectRowCount", int(2 * cls.height_multiplier)) 
    
    @classmethod
    def set_game_system_select_col_count(cls, count):
        cls._data["gameSystemSelectColCount"] = count
        cls.save_changes()


    @classmethod
    def get_game_system_select_carousel_col_count(cls):
        return cls._data.get("gameSystemSelectCarouselColCount", cls.get_game_system_select_col_count())
    
    @classmethod
    def set_game_system_select_carousel_col_count(cls, count):
        cls._data["gameSystemSelectCarouselColCount"] = count
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
        return cls._data.get("popupMenuTextPad", int(20*cls._default_multiplier))

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
        return cls._data.get("mainMenuColCount", int(4 * cls.width_multiplier))

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
        return cls._data.get("gameSelectRowCount", int(2 * cls.height_multiplier)) 

    @classmethod
    def set_game_select_row_count(cls, value):
        cls._data["gameSelectRowCount"] = value
        cls.save_changes()

    @classmethod
    def get_game_select_col_count(cls, default_value=None):
        if default_value is not None:
            return cls._data.get("gameSelectColCount", default_value)
        return cls._data.get("gameSelectColCount", int(4*cls.width_multiplier)) 

    @classmethod
    def set_game_select_col_count(cls, value):
        cls._data["gameSelectColCount"] = value
        cls.save_changes()

    @classmethod
    def get_game_select_carousel_col_count(cls):
        return cls._data.get("gameSelectCarouselColCount", cls.get_game_select_col_count(int(3*cls.width_multiplier))) 

    @classmethod
    def set_game_select_carousel_col_count(cls, value):
        cls._data["gameSelectCarouselColCount"] = value
        cls.save_changes()

    @classmethod
    def get_game_select_img_width(cls):
        return cls._data.get("gameSelectImgWidth", int(320 * cls._default_multiplier))
    
    @classmethod
    def set_game_select_img_width(cls, value):
        cls._data["gameSelectImgWidth"] = value
        cls.save_changes()

    @classmethod
    def get_grid_game_select_img_width(cls):
        return cls._data.get("gridGameSelectImgWidth", int(cls._grid_game_default_size * cls._default_multiplier))
    
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
    def get_grid_system_select_img_width(cls):
        return cls._data.get("gridSystemSelectImgWidth", int(cls._grid_game_default_size * cls._default_multiplier))
    
    @classmethod
    def set_grid_system_select_img_width(cls, value):
        cls._data["gridSystemSelectImgWidth"] = value
        cls.save_changes()

    @classmethod
    def get_list_system_select_img_width(cls):
        return cls._data.get("listSystemSelectImgWidth", cls.get_game_select_img_width())
    
    @classmethod
    def set_list_system_select_img_width(cls, value):
        cls._data["listSystemSelectImgWidth"] = value
        cls.save_changes()

    @classmethod
    def get_carousel_game_select_primary_img_width(cls):
        return cls._data.get("carouselGameSelectPrimaryImgWidth", 50)
    
    @classmethod
    def set_carousel_game_select_primary_img_width(cls, value):
        cls._data["carouselGameSelectPrimaryImgWidth"] = value
        cls.save_changes()

    @classmethod
    def get_carousel_system_select_primary_img_width(cls):
        return cls._data.get("carouselSystemSelectPrimaryImgWidth", 40)
    
    @classmethod
    def set_carousel_system_select_primary_img_width(cls, value):
        cls._data["carouselSystemSelectPrimaryImgWidth"] = value
        cls.save_changes()

    @classmethod
    def get_carousel_game_select_shrink_further_away(cls):
        return cls._data.get("carouselGameSelectShrinkFurtherAway", False)
    
    @classmethod
    def set_carousel_game_select_shrink_further_away(cls, value):
        cls._data["carouselGameSelectShrinkFurtherAway"] = value
        cls.save_changes()

    @classmethod
    def get_carousel_system_select_shrink_further_away(cls):
        return cls._data.get("carouselSystemSelectShrinkFurtherAway", False)
    
    @classmethod
    def set_carousel_system_select_shrink_further_away(cls, value):
        cls._data["carouselSystemSelectShrinkFurtherAway"] = value
        cls.save_changes()

    @classmethod
    def get_carousel_game_select_sides_hang_off(cls):
        return cls._data.get("carouselGameSelectSidesHangOff", False)

    @classmethod
    def set_carousel_game_select_sides_hang_off(cls, value):
        cls._data["carouselGameSelectSidesHangOff"] = value
        cls.save_changes()   

    @classmethod
    def get_carousel_system_select_sides_hang_off(cls):
        return cls._data.get("carouselSystemSelectSidesHangOff", True)

    @classmethod
    def set_carousel_system_select_sides_hang_off(cls, value):
        cls._data["carouselSystemSelectSidesHangOff"] = value
        cls.save_changes()    

    @classmethod
    def get_game_select_img_height(cls):
        return cls._data.get("gameSelectImgHeight", int(300 * cls._default_multiplier))
    
    @classmethod
    def set_game_select_img_height(cls, value):
        cls._data["gameSelectImgHeight"] = value
        cls.save_changes()

    @classmethod
    def get_grid_game_select_img_height(cls):
        return cls._data.get("gridGameSelectImgHeight", int(cls._grid_game_default_size * cls._default_multiplier))
    
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
    def get_grid_system_select_img_height(cls):
        return cls._data.get("gridSystemSelectImgHeight", int(cls._grid_game_default_size * cls._default_multiplier))
    
    @classmethod
    def set_grid_system_select_img_height(cls, value):
        cls._data["gridSystemSelectImgHeight"] = value
        cls.save_changes()

    @classmethod
    def get_list_system_select_img_height(cls):
        return cls._data.get("listSystemSelectImgHeight", cls.get_game_select_img_height())
    
    @classmethod
    def set_list_system_select_img_height(cls, value):
        cls._data["listSystemSelectImgHeight"] = value
        cls.save_changes()

    @classmethod
    def get_set_top_bar_text_to_game_selection(cls):
        return cls._data.get("setTopBarTextToGameSelection", False)
    
    @classmethod
    def set_set_top_bar_text_to_game_selection(cls, value):
        cls._data["setTopBarTextToGameSelection"] = value
        cls.save_changes()

    @classmethod
    def get_system_select_grid_wrap_around_single_row(cls):
        return cls._data.get("systemSelectGridWrapAroundSingleRow", True)
    
    @classmethod
    def set_system_select_grid_wrap_around_single_row(cls, value):
        cls._data["systemSelectGridWrapAroundSingleRow"] = value
        cls.save_changes()
        
    @classmethod
    def set_set_top_bar_text_to_game_selection(cls, value):
        cls._data["setTopBarTextToGameSelection"] = value
        cls.save_changes()

    @classmethod
    def get_main_menu_grid_wrap_around_single_row(cls):
        return cls._data.get("mainMenuGridWrapAroundSingleRow", False)
    
    @classmethod
    def set_main_menu_grid_wrap_around_single_row(cls, value):
        cls._data["mainMenuGridWrapAroundSingleRow"] = value
        cls.save_changes()

    @classmethod
    def skip_main_menu(cls):
        return cls._data.get("skipMainMenu", False)

    @classmethod
    def set_skip_main_menu(cls, value):
        cls._data["skipMainMenu"] = value
        cls.save_changes()

    @classmethod
    def merge_main_menu_and_game_menu(cls):
        return cls._data.get("mergeMainMenuAndGameMenu", False)

    @classmethod
    def set_merge_main_menu_and_game_menu(cls, value):
        cls._data["mergeMainMenuAndGameMenu"] = value
        cls.save_changes()

    @classmethod
    def show_extras_in_system_select_menu(cls):
        return cls._data.get("showExtrasInSystemSelectMenu", False)

    @classmethod
    def set_show_extras_in_system_select_menu(cls, value):
        cls._data["showExtrasInSystemSelectMenu"] = value
        cls.save_changes()

    @classmethod
    def get_grid_multi_row_sel_bg_resize_pad_width(cls):
        return cls._data.get("gridMultiRowSelBgResizePadWidth", int(20*cls._default_multiplier))
    
    @classmethod
    def set_grid_multi_row_sel_bg_resize_pad_width(cls, value):
        cls._data["gridMultiRowSelBgResizePadWidth"] = value
        cls.save_changes()

    @classmethod
    def get_grid_multi_row_sel_bg_resize_pad_height(cls):
        return cls._data.get("gridMultiRowSelBgResizePadHeight", int(20*cls._default_multiplier))
    
    @classmethod
    def set_grid_multi_row_sel_bg_resize_pad_height(cls, value):
        cls._data["gridMultiRowSelBgResizePadHeight"] = value
        cls.save_changes()

    @classmethod
    def get_top_bar_initial_x_offset(cls):
        return cls._data.get("topBarInitialXOffset", int(20*cls._default_multiplier))

    @classmethod
    def set_top_bar_initial_x_offset(cls, value):
        cls._data["topBarInitialXOffset"] = value
        cls.save_changes()
    
    @classmethod
    def get_grid_multi_row_img_y_offset(cls, text_height):
        default_height = -25
        if(0 != text_height):
            default_height = -1 * text_height        

        return default_height + cls._data.get("gridMultiRowImageYOffset", 0)

    @classmethod
    def get_grid_multi_row_img_y_offset_raw(cls):
        return cls._data.get("gridMultiRowImageYOffset", 0)

    @classmethod
    def set_grid_multi_row_img_y_offset(cls, value):
        cls._data["gridMultiRowImageYOffset"] = value
        cls.save_changes()

    @classmethod
    def get_app_icon(cls, app_name):
        qoi_name = os.path.splitext(app_name)[0] + ".qoi"
        return cls._icon("app",qoi_name)

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
    def get_full_screen_grid_system_select_menu_resize_type(cls):
        view_type_str = cls._data.get("fullScreenGridSystemSelectMenuResizeType", "ZOOM")
        return getattr(ResizeType, view_type_str, ResizeType.ZOOM)


    @classmethod
    def set_full_screen_grid_system_select_menu_resize_type(cls, resize_type):
        cls._data["fullScreenGridSystemSelectMenuResizeType"] = resize_type.name
        cls.save_changes()


    @classmethod
    def get_set_top_bar_text_to_game_selection_for_game_switcher(cls):
        return cls._data.get("gameSwitcherSetTopBarTextToGameSelection", True)
    
    @classmethod
    def set_set_top_bar_text_to_game_selection_for_game_switcher(cls, value):
        cls._data["gameSwitcherSetTopBarTextToGameSelection"] = value
        cls.save_changes()

    @classmethod
    def true_full_screen_game_switcher(cls):
        return cls._data.get("gameSwitcherTrueFullScreen", True)
    
    @classmethod
    def set_true_full_screen_game_switcher(cls, value):
        cls._data["gameSwitcherTrueFullScreen"] = value
        cls.save_changes()

    @classmethod
    def display_battery_percent(cls):
        return cls._data.get("displayBatteryPercent", True)
    
    @classmethod
    def set_display_battery_percent(cls, value):
        cls._data["displayBatteryPercent"] = value
        cls.save_changes()

    @classmethod
    def display_battery_icon(cls):
        return cls._data.get("displayBatteryIcon", True)
    
    @classmethod
    def set_display_battery_icon(cls, value):
        cls._data["displayBatteryIcon"] = value
        cls.save_changes()

    @classmethod
    def display_volume_numbers(cls):
        return cls._data.get("displayVolumeNumbers", False)
        
    @classmethod
    def set_display_volume_numbers(cls, value):
        cls._data["displayVolumeNumbers"] = value
        cls.save_changes()

    @classmethod
    def show_bottom_bar_buttons(cls):
        return cls._data.get("showBottomBarButtons", True)
        
    @classmethod
    def set_show_bottom_bar_buttons(cls, value):
        cls._data["showBottomBarButtons"] = value
        cls.save_changes()

    @classmethod
    def get_main_menu_title(cls):
        return cls._data.get("mainMenuTitle", PyUiConfig.get_main_menu_title())
    
    @classmethod
    def set_main_menu_title(cls, value):
        cls._data["mainMenuTitle"] = value
        cls.save_changes()

    @classmethod
    def show_clock(cls):
        return cls._data.get("showClock", True)

    @classmethod
    def set_show_clock(cls, value):
        cls._data["showClock"] = value
        cls.save_changes()

    @classmethod
    def grid_bg_offset_to_image_offset(cls):
        return cls._data.get("gridBgOffsetToImageOffset", False)

    @classmethod
    def set_grid_bg_offset_to_image_offset(cls, value):
        cls._data["gridBgOffsetToImageOffset"] = value
        cls.save_changes()

    @classmethod
    def single_row_grid_text_y_offset(cls):
        return cls._data.get("singleRowGridTextYOffset", 0)

    @classmethod
    def set_single_row_grid_text_y_offset(cls, value):
        cls._data["singleRowGridTextYOffset"] = value
        cls.save_changes()

    @classmethod
    def multi_row_grid_text_y_offset(cls):
        return cls._data.get("multiRowGridTextYOffset", 0)

    @classmethod
    def set_multi_row_grid_text_y_offset(cls, value):
        cls._data["multiRowGridTextYOffset"] = value
        cls.save_changes()

    @classmethod
    def check_and_create_asset(cls, output_image, input_image, target_width, target_height, target_alpha_channel):
        if(not os.path.exists(output_image)):
            PyUiLogger.get_logger().info(f"Creating resized {output_image} from {input_image}")      
            Device.get_device().get_image_utils().resize_image(input_image,
                                                  output_image,
                                                  target_width,
                                                  target_height,
                                                  preserve_aspect_ratio=False,
                                                  target_alpha_channel=target_alpha_channel)

    @classmethod
    def check_and_create_ra_assets(cls):  
        cls.check_and_create_asset( cls._resolve_png_path(cls._skin_folder,["menu-6line-bg.png"]),
                                    cls._resolve_png_path(cls._skin_folder,["background.png"]),
                                    320,
                                    420,
                                    0.75)

        cls.check_and_create_asset( cls._resolve_png_path(cls._skin_folder,["list-item-select-bg-short.png"]),
                                    cls._resolve_png_path(cls._skin_folder,["bg-list-s.png"]),
                                    320,
                                    60,
                                    1.00)



    @classmethod
    def get_cfw_default_icon(cls, icon_name):
        cfw_theme = PyUiConfig.get("theme")
        PyUiLogger.get_logger().debug(f"Getting CFW default icon '{icon_name}' for theme '{cfw_theme}'")
        if(cfw_theme is None):
            PyUiLogger.get_logger().debug(f"CFW theme is None, cannot get icon")
            return None
        else:
            cfw_theme_path = os.path.join(PyUiConfig.get("themeDir"),cfw_theme)
            PyUiLogger.get_logger().debug(f"cfw_theme_path is '{cfw_theme_path}'")
            path = os.path.join(cfw_theme_path, 
                                cls._get_asset_folder(cfw_theme_path, "icons", 
                                                      Device.get_device().screen_width(), 
                                                      Device.get_device().screen_height()), 
                                "app",icon_name)

            PyUiLogger.get_logger().debug(f"icon path resolved to '{path}'")
            if os.path.exists(path):
                return path

            # Fallback only makes sense for .qoi assets/icons
            if path.endswith(".qoi"):
                png_path = path[:-4] + ".png"
                if os.path.exists(png_path):
                    return png_path

            return None
        

    @classmethod
    def get_relative_img(cls, img_path, folder):    
        if not img_path:
            return None
        p = Path(img_path)

        if not p.exists():
            return None

        bg_path = p.parent / folder / p.name

        if not bg_path.exists():
            return None

        return str(bg_path)

    @classmethod
    def get_bg_for_img(cls, img_path):
        return cls.get_relative_img(img_path, "bg")
    
    @classmethod
    def get_overlay_for_img(cls, img_path):
        return cls.get_relative_img(img_path, "overlay")
