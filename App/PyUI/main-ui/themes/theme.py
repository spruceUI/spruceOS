import json
import os

from devices.charge.charge_status import ChargeStatus
from devices.wifi.wifi_status import WifiStatus
from display.font_purpose import FontPurpose
from display.resize_type import ResizeType
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
        from display.display import Display
        Display.clear_cache()

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
    def _grid_multi_row_selected_bg(cls):
        return cls._asset("bg-game-item-f.png")

    @classmethod
    def _grid_single_row_selected_bg(cls):
        return cls._asset("bg-game-item-single-f.png")

    @classmethod
    def get_grid_game_selected_bg(cls):
        return cls._asset("grid-game-selected.png")

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
                case _:
                    return cls._data["list"]["font"]
        except Exception as e:
            PyUiLogger.get_logger().error(f"get_font_size error occurred: {e}")
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
                case _:
                    PyUiLogger.get_logger().error(
                        f"set_font_size: Unknown font purpose {font_purpose}")
                
            cls.save_changes()
        except Exception as e:
            PyUiLogger.get_logger().error(f"get_font_size error occurred: {e}")


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
        return cls._data.get("gameSelectShowTextGridMode", True)
    
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
        view_type_str = cls._data.get("gameSelectGridResizeType", "FIT")
        return getattr(ResizeType, view_type_str, ResizeType.FIT)

    @classmethod
    def set_grid_game_selected_resize_type(cls, view_type):
        cls._data["gameSelectGridResizeType"] = view_type.name
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
        return cls._data.get("mainMenuOrdering", ["Recent", "Favorite", "Game", "App", "Setting"])

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
    def get_game_select_img_height(cls):
        from devices.device import Device
        return cls._data.get("gameSelectImgHeight", int(Device.screen_height() * 300 / 640))
    
    @classmethod
    def set_game_select_img_height(cls, value):
        cls._data["gameSelectImgHeight"] = value
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
    def get_grid_multi_row_extra_y_pad(cls):
        return cls._data.get("gridMultiRowExtraYPad", 17)
    
    @classmethod
    def set_grid_multi_row_extra_y_pad(cls, value):
        cls._data["gridMultiRowExtraYPad"] = value
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


    