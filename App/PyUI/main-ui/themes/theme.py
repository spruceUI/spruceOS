import json
import os

from devices.charge.charge_status import ChargeStatus
from devices.wifi.wifi_status import WifiStatus
from display.font_purpose import FontPurpose
from utils.logger import PyUiLogger
from views.view_type import ViewType

class Theme():
    _data = {}
    _path = ""
    _skin_folder = ""
    _icon_folder = ""
    _loaded_file_path = ""

    @classmethod
    def init(cls, path, width, height):
        cls.set_theme_path(path, width, height)
    
    @classmethod
    def set_theme_path(cls,path, width = 0, height = 0):
        cls._data.clear()
        cls._path = path
        cls._load_defaults()

        resolution_specific_config = f"config_{width}x{height}.json"
        config_path = os.path.join(path, resolution_specific_config)
        if os.path.exists(config_path):
            cls._load_from_file(config_path)
            PyUiLogger.get_logger().info(f"Resolution specific config found, using {resolution_specific_config}")
        else:
            cls._load_from_file(os.path.join(path, "config.json"))
            PyUiLogger.get_logger().info(f"No resolution specific config {config_path} found, using config.json")

        cls._path = path
        cls._skin_folder = cls._get_asset_folder("skin", width, height)
        cls._icon_folder = cls._get_asset_folder("icons", width, height)

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
        cls._loaded_file_path = file_path
        with open(file_path, 'r', encoding='utf-8') as f:
            cls._data.update(json.load(f))
        desc = cls._data.get("description", "UNKNOWN")
        PyUiLogger.get_logger().info(f"Loaded Theme : {desc}")
     
    @classmethod
    def save_changes(cls):
        data = {
            key: value for key, value in cls._data.items()
            if not key.startswith('_') and not callable(value)
        }
        with open(cls._loaded_file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
        PyUiLogger.get_logger().info(f"Wrote Theme : {cls._data.get('description', 'UNKNOWN')}")

    @classmethod
    def _asset(cls, *parts):
        return os.path.join(cls._path, cls._skin_folder, *parts)
    
    @classmethod
    def _icon(cls, *parts):
        return os.path.join(cls._path, cls._icon_folder, *parts)

    @classmethod
    def background(cls): return cls._asset("background.png")
    
    @classmethod
    def favorite(cls): return cls._asset("ic-favorite-n.png")
    
    @classmethod
    def favorite_selected(cls): return cls._asset("ic-favorite-f.png")
    
    @classmethod
    def recent(cls): return cls._asset("ic-recent-n.png")
    
    @classmethod
    def recent_selected(cls): return cls._asset("ic-recent-f.png")
    
    @classmethod
    def game(cls): return cls._asset("ic-game-n.png")
    
    @classmethod
    def game_selected(cls): return cls._asset("ic-game-f.png")
    
    @classmethod
    def app(cls): return cls._asset("ic-app-n.png")
    
    @classmethod
    def app_selected(cls): return cls._asset("ic-app-f.png")
    
    @classmethod
    def settings(cls): return cls._asset("ic-setting-n.png")
    
    @classmethod
    def settings_selected(cls): return cls._asset("ic-setting-f.png")
    
    @classmethod
    def get_title_bar_bg(cls): return cls._asset("bg-title.png")
    
    @classmethod
    def bottom_bar_bg(cls): return cls._asset("tips-bar-bg.png")
    
    @classmethod
    def confirm_icon(cls): return cls._asset("icon-A-54.png")
    
    @classmethod
    def back_icon(cls): return cls._asset("icon-B-54.png")
    
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
    def favorite_icon(cls): return cls._asset("ic-favorite-mark.png")
    
    @classmethod
    def get_list_large_selected_bg(cls): return cls._asset("bg-list-l.png")
   
    @classmethod
    def menu_popup_bg_large(cls): return cls._asset("bg-pop-menu-4.png")
    
    @classmethod
    def keyboard_bg(cls): return cls._asset("bg-grid-s.png")
    
    @classmethod
    def keyboard_entry_bg(cls): return cls._asset("bg-list-l.png")
    
    @classmethod
    def key_bg(cls): return cls._asset("bg-btn-01-n.png")
    
    @classmethod
    def key_selected_bg(cls): return cls._asset("bg-btn-01-f.png")
    
    @classmethod
    def get_list_small_selected_bg(cls): return cls._asset("bg-list-s.png")
    
    @classmethod
    def get_popup_menu_selected_bg(cls): return cls._asset("bg-list-s2.png")
    
    @classmethod
    def get_battery_icon(cls, charging, battery_percent):
        if ChargeStatus.CHARGING == charging:
            if battery_percent > 97:
                return cls._asset("ic-power-charge-100%.png")
            elif battery_percent >= 75:
                return cls._asset("ic-power-charge-75%.png")
            elif battery_percent >= 50:
                return cls._asset("ic-power-charge-50%.png")
            elif battery_percent >= 25:
                return cls._asset("ic-power-charge-25%.png")
            else:
                return cls._asset("ic-power-charge-0%.png")
        else:
            if battery_percent >= 97:
                return cls._asset("power-full-icon.png")
            elif battery_percent >= 80:
                return cls._asset("power-80%-icon.png")
            elif battery_percent >= 50:
                return cls._asset("power-50%-icon.png")
            elif battery_percent >= 20:
                return cls._asset("power-20%-icon.png")
            else:
                return cls._asset("power-0%-icon.png")
            
    @classmethod
    def get_wifi_icon(cls, status):
        if status == WifiStatus.OFF:
            return cls._asset("icon-wifi-locked.png")
        elif status == WifiStatus.BAD:
            return cls._asset("icon-wifi-signal-01.png")
        elif status == WifiStatus.OKAY:
            return cls._asset("icon-wifi-signal-02.png")
        elif status == WifiStatus.GOOD:
            return cls._asset("icon-wifi-signal-03.png")
        elif status == WifiStatus.GREAT:
            return cls._asset("icon-wifi-signal-04.png")
        else:
            return cls._asset("icon-wifi-locked.png")
        
    @classmethod
    def system(cls, system):
        return os.path.join(cls._path, cls._icon_folder, system.lower() + ".png")
    @classmethod
    def system_selected(cls, system):
        return os.path.join(cls._path, cls._icon_folder, "sel", system.lower() + ".png")
    @classmethod
    def _grid_4_x_2_selected_bg(cls):
        return cls._asset("bg-game-item-f.png")

    @classmethod
    def get_system_icon(cls, system):
        return os.path.join(cls._path, cls._icon_folder, system + ".png")
   
    @classmethod
    def get_system_icon_selected(cls, system):
        return os.path.join(cls._path, cls._icon_folder, "sel", system + ".png")

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
                case _:
                    font = os.path.join(cls._path,cls._data["list"]["font"]) 
                
            if os.path.exists(font):
                return font 
            else:
                return "/mnt/SDCARD/Themes/STOCK/nunwen.ttf"
        except Exception as e:
            PyUiLogger.get_logger().error(f"get_font error occurred: {e}")
            return "/mnt/SDCARD/Themes/STOCK/nunwen.ttf"

    @classmethod
    def get_font_size(cls, font_purpose : FontPurpose):
        try:
            match font_purpose:
                case FontPurpose.TOP_BAR_TEXT:
                    return cls._data["list"].get("size", 24)
                case FontPurpose.BATTERY_PERCENT:
                    return cls._data["list"].get("size", 24)
                case FontPurpose.ON_SCREEN_KEYBOARD:
                    return cls._data["list"].get("size", 24)
                case FontPurpose.GRID_ONE_ROW:
                    return cls._data["grid"].get("grid1x4", cls._data["grid"].get("size",25))
                case FontPurpose.GRID_MULTI_ROW:
                    return cls._data["grid"].get("grid3x4", cls._data["grid"].get("size",18))
                case FontPurpose.LIST:
                    return cls._data["list"].get("size", 24)
                case FontPurpose.DESCRIPTIVE_LIST_TITLE:
                    return cls._data["list"].get("size", 24)
                case FontPurpose.MESSAGE:
                    return cls._data["list"].get("size", 24)
                case FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION:
                    return cls._data["grid"].get("grid3x4", cls._data["grid"].get("size",18))
                case FontPurpose.LIST_INDEX:
                    return cls._data.currentpage.get("size", 22)
                case FontPurpose.LIST_TOTAL:
                    return cls._data.total.get("size", 22)
                case _:
                    return cls._data["list"]["font"]
        except Exception as e:
            PyUiLogger.get_logger().error(f"get_font_size error occurred: {e}")
            return 20

    @classmethod
    def text_color(cls, font_purpose : FontPurpose):
        try:
            match font_purpose:
                case FontPurpose.TOP_BAR_TEXT:
                    if(cls._data["title"] and cls._data["title"]["color"]):
                        return cls.hex_to_color(cls._data["title"]["color"])
                    else:
                        return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.BATTERY_PERCENT:
                    if(cls._data["batteryPercentage"] and cls._data["batteryPercentage"]["color"]):
                        return cls.hex_to_color(cls._data["batteryPercentage"]["color"])
                    else:
                        return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.ON_SCREEN_KEYBOARD:
                    return cls.hex_to_color(cls._data["grid"]["color"])
                case FontPurpose.GRID_ONE_ROW:
                    return cls.hex_to_color(cls._data["grid"]["color"])
                case FontPurpose.GRID_MULTI_ROW:
                    return cls.hex_to_color(cls._data["grid"]["color"])
                case FontPurpose.LIST:
                    return cls.hex_to_color(cls._data["grid"]["color"])
                case FontPurpose.DESCRIPTIVE_LIST_TITLE:
                    return cls.hex_to_color(cls._data["grid"]["color"])
                case FontPurpose.MESSAGE:
                    return cls.hex_to_color(cls._data["grid"]["color"])
                case FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION:
                    return cls.hex_to_color(cls._data["grid"]["color"])
                case FontPurpose.LIST_INDEX:
                    return cls.hex_to_color(cls._data.currentpage["color"])
                case FontPurpose.LIST_TOTAL:
                    return cls.hex_to_color(cls._data.total["color"])
                case _:
                    return cls.hex_to_color(cls._data["grid"]["color"])
        except Exception as e:
            return cls.hex_to_color("#808080")
      
    @classmethod
    def text_color_selected(cls, font_purpose : FontPurpose):
        try:
            match font_purpose:
                case FontPurpose.GRID_ONE_ROW:
                    return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.GRID_MULTI_ROW:
                    return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.LIST:
                    return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.DESCRIPTIVE_LIST_TITLE:
                    return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.MESSAGE:
                    return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION:
                    return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
                case FontPurpose.LIST_INDEX:
                    return cls.hex_to_color(cls._data.currentpage["selectedcolor"])
                case FontPurpose.LIST_TOTAL:
                    return cls.hex_to_color(cls._data.total["color"])
                case FontPurpose.ON_SCREEN_KEYBOARD:
                    return cls.hex_to_color(cls._data["grid"]["selectedcolor"])
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
        return cls._data.get("showBottomBar", None)

    @classmethod
    def get_descriptive_list_icon_offset_y(cls):
        return cls._data.get("descriptiveListIconOffsetY", 10)

    @classmethod
    def get_descriptive_list_text_offset_y(cls):
        return cls._data.get("descriptiveListTextOffsetY", 15)

    @classmethod
    def get_descriptive_list_text_from_icon_offset(cls):
        return cls._data.get("descriptiveListTextFromIconOffset", 20)

    @classmethod
    def get_grid_multirow_text_offset_y(cls):
        return cls._data.get("gridMultirowTextOffsetY", -25)

    @classmethod
    def get_grid_bg(cls, rows, cols):
        if rows > 1:
            # TODO better handle this dynamically
            return cls._grid_4_x_2_selected_bg()
        else:
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
    def rom_image_width(cls, device_width):
        return int(device_width * 294 / 640)

    @classmethod
    def rom_image_height(cls, device_height):
        if cls._data.get("showBottomBar", False):
            return int(device_height * 300 / 640)
        else:
            return int(device_height * 340 / 640)

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
    def get_main_menu_column_count(cls):
        return cls._data.get("mainMenuColCount", 4)

    @classmethod
    def get_game_selection_view_type(cls):
        view_type_str = cls._data.get("gameSelectionViewType", "TEXT_AND_IMAGE")
        return getattr(ViewType, view_type_str, ViewType.TEXT_AND_IMAGE)

    @classmethod
    def set_game_selection_view_type(cls, view_type):
        cls._data["gameSelectionViewType"] = view_type.name
        cls.save_changes()

    @classmethod
    def set_main_menu_column_count(cls, count):
        cls._data["mainMenuColCount"] = count
        cls.save_changes()

    