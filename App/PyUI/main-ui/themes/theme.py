import json
import os

from devices.charge.charge_status import ChargeStatus
from devices.wifi.wifi_status import WifiStatus
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from utils.logger import PyUiLogger
from views.view_type import ViewType

class Theme():
    
    def __init__(self, path):
        self.set_theme_path(path)

    def set_theme_path(self,path):
        self.__dict__.clear()
        self.path = path
        self.load_defaults_for_values_not_in_miyoo_theme()
        self.load_from_file(os.path.join(path,"config.json"))
        #Reload path incase a theme tried to set it
        self.path = path

    def load_defaults_for_values_not_in_miyoo_theme(self):
        setattr(self, "showBottomBar", True)

    def load_from_file(self, file_path):
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        # Store top-level keys as attributes
        for key, value in data.items():
            setattr(self, key, value)

        description = getattr(self, "description", "UNKNOWN")
        PyUiLogger.get_logger().info(f"Loaded Theme : {description}")
     

    @property
    def background(self):
        return os.path.join(self.path,"skin","background.png")

    @property
    def favorite(self):
        return os.path.join(self.path,"skin","ic-favorite-n.png")

    @property
    def favorite_selected(self):
        return os.path.join(self.path,"skin","ic-favorite-f.png")

    @property
    def game(self):
        return os.path.join(self.path,"skin","ic-game-n.png")

    @property
    def game_selected(self):
        return os.path.join(self.path,"skin","ic-game-f.png")

    @property
    def app(self):
        return os.path.join(self.path,"skin","ic-app-n.png")
    
    @property
    def app_selected(self):
        return os.path.join(self.path,"skin","ic-app-f.png")

    @property
    def settings(self):
        return os.path.join(self.path,"skin","ic-setting-n.png")

    @property
    def settings_selected(self):
        return os.path.join(self.path,"skin","ic-setting-f.png")

    @property
    def get_title_bar_bg(self):
        return os.path.join(self.path,"skin","bg-title.png")

    @property
    def show_bottom_bar(self):
        return getattr(self, "showBottomBar", None) is not False

    def ignore_top_and_bottom_bar_for_layout(self):
        return getattr(self, "ignoreTopAndBottomBarForLayout", False)
    
    def show_top_bar_text(self):
        return getattr(self, "showTopBarText", True)
    
    def render_top_and_bottom_bar_last(self):
        return getattr(self, "renderTopAndBottomBarLast", False)

    @property
    def bottom_bar_bg(self):
        return os.path.join(self.path,"skin","tips-bar-bg.png")

    @property
    def confirm_icon(self):
        return os.path.join(self.path,"skin","icon-A-54.png")

    @property
    def back_icon(self):
        return os.path.join(self.path,"skin","icon-B-54.png")

    @property
    def confirm_text(self):
        return "Okay"
    
    @property
    def back_text(self):
        return "Back"

    @property
    def favorite_icon(self):
        return os.path.join(self.path,"skin","ic-favorite-mark.png")

    def get_list_large_selected_bg(self):
        return os.path.join(self.path,"skin","bg-list-l.png")

    @property
    def menu_popup_bg_large(self):
        return os.path.join(self.path,"skin","bg-pop-menu-4.png")

    @property
    def keyboard_bg(self):
        return os.path.join(self.path,"skin","bg-grid-s.png")

    @property
    def keyboard_entry_bg(self):
        return os.path.join(self.path,"skin","bg-list-l.png")

    @property
    def key_bg(self):
        return os.path.join(self.path,"skin","bg-btn-01-n.png")

    @property
    def key_selected_bg(self):
        return os.path.join(self.path,"skin","bg-btn-01-f.png")

    def get_list_small_selected_bg(self):
        return os.path.join(self.path,"skin","bg-list-s.png")
    
    def get_popup_menu_selected_bg(self):
        return os.path.join(self.path,"skin","bg-list-s2.png")
    
    def get_battery_icon(self,charging,battery_percent):
        if(ChargeStatus.CHARGING == charging):
            if(battery_percent > 97):
                return os.path.join(self.path,"skin","ic-power-charge-100%.png")
            elif(battery_percent >= 75):
                return os.path.join(self.path,"skin","ic-power-charge-75%.png")
            elif(battery_percent >= 50):
                return os.path.join(self.path,"skin","ic-power-charge-50%.png")
            elif(battery_percent >= 25):
                return os.path.join(self.path,"skin","ic-power-charge-25%.png")
            else:
                return os.path.join(self.path,"skin","ic-power-charge-0%.png")
        else:
            if(battery_percent >= 97):
                return os.path.join(self.path,"skin","power-full-icon.png")
            elif(battery_percent >= 80):
                return os.path.join(self.path,"skin","power-80%-icon.png")
            elif(battery_percent >= 50):
                return os.path.join(self.path,"skin","power-50%-icon.png")
            elif(battery_percent >= 20):
                return os.path.join(self.path,"skin","power-20%-icon.png")
            else:
                return os.path.join(self.path,"skin","power-0%-icon.png")

    def get_wifi_icon(self,status):
        if status == WifiStatus.OFF:
            return os.path.join(self.path,"skin","icon-wifi-locked.png")
        elif status == WifiStatus.BAD:
            return os.path.join(self.path,"skin","icon-wifi-signal-01.png")
        elif status == WifiStatus.OKAY:
            return os.path.join(self.path,"skin","icon-wifi-signal-02.png")
        elif status == WifiStatus.GOOD:
            return os.path.join(self.path,"skin","icon-wifi-signal-03.png")
        elif status == WifiStatus.GREAT:
            return os.path.join(self.path,"skin","icon-wifi-signal-04.png")
        else:
            return os.path.join(self.path,"skin","icon-wifi-locked.png")

    def system(self, system):
        return os.path.join(self.path,"icons",system.lower() +".png")
    
    def system_selected(self, system):
        return os.path.join(self.path,"icons","sel",system.lower() +".png")
    
    def _grid_4_x_2_selected_bg(self):
        return os.path.join(self.path,"skin","bg-game-item-f.png")
    
    def get_system_icon(self, system):
        return os.path.join(self.path,"icons",system+".png")
    
    def get_system_icon_selected(self, system):
        return os.path.join(self.path,"icons","sel",system+".png")
    
    
    def get_font(self, font_purpose : FontPurpose):
        try:
            match font_purpose:
                case FontPurpose.TOP_BAR_TEXT:
                    font = os.path.join(self.path,self.list["font"]) 
                case FontPurpose.BATTERY_PERCENT:
                    font = os.path.join(self.path,self.list["font"]) 
                case FontPurpose.ON_SCREEN_KEYBOARD:
                    font = os.path.join(self.path,self.list["font"]) 
                case FontPurpose.GRID_ONE_ROW:
                    font = os.path.join(self.path,self.grid["font"]) 
                case FontPurpose.GRID_MULTI_ROW:
                    font = os.path.join(self.path,self.grid["font"]) 
                case FontPurpose.LIST:
                    font = os.path.join(self.path,self.list["font"]) 
                case FontPurpose.DESCRIPTIVE_LIST_TITLE:
                    font = os.path.join(self.path,self.list["font"]) 
                case FontPurpose.MESSAGE:
                    font = os.path.join(self.path,self.list["font"]) 
                case FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION:
                    font = os.path.join(self.path,self.list["font"]) 
                case _:
                    font = os.path.join(self.path,self.list["font"]) 
                
            if os.path.exists(font):
                return font 
            else:
                return "/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf"
        except Exception as e:
            PyUiLogger.get_logger().error(f"get_font error occurred: {e}")
            return "/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf"

    
    def get_font_size(self, font_purpose : FontPurpose):
        try:
            match font_purpose:
                case FontPurpose.TOP_BAR_TEXT:
                    return self.list.get("size", 24)
                case FontPurpose.BATTERY_PERCENT:
                    return self.list.get("size", 24)
                case FontPurpose.ON_SCREEN_KEYBOARD:
                    return self.list.get("size", 24)
                case FontPurpose.GRID_ONE_ROW:
                    return self.grid.get("grid1x4", self.grid.get("size",25))
                case FontPurpose.GRID_MULTI_ROW:
                    return self.grid.get("grid3x4", self.grid.get("size",18))
                case FontPurpose.LIST:
                    return self.list.get("size", 24)
                case FontPurpose.DESCRIPTIVE_LIST_TITLE:
                    return self.list.get("size", 24)
                case FontPurpose.MESSAGE:
                    return self.list.get("size", 24)
                case FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION:
                    return self.grid.get("grid3x4", self.grid.get("size",18))
                case FontPurpose.LIST_INDEX:
                    return self.currentpage.get("size", 22)
                case FontPurpose.LIST_TOTAL:
                    return self.total.get("size", 22)
                case _:
                    return self.list["font"]
        except Exception as e:
            PyUiLogger.get_logger().error(f"get_font_size error occurred: {e}")
            return 20

    def text_color(self, font_purpose : FontPurpose):
        try:
            match font_purpose:
                case FontPurpose.TOP_BAR_TEXT:
                    return self.hex_to_color(self.grid["selectedcolor"])
                case FontPurpose.BATTERY_PERCENT:
                    return self.hex_to_color(self.grid["selectedcolor"])
                case FontPurpose.ON_SCREEN_KEYBOARD:
                    return self.hex_to_color(self.grid["color"])
                case FontPurpose.GRID_ONE_ROW:
                    return self.hex_to_color(self.grid["color"])
                case FontPurpose.GRID_MULTI_ROW:
                    return self.hex_to_color(self.grid["color"])
                case FontPurpose.LIST:
                    return self.hex_to_color(self.grid["color"])
                case FontPurpose.DESCRIPTIVE_LIST_TITLE:
                    return self.hex_to_color(self.grid["color"])
                case FontPurpose.MESSAGE:
                    return self.hex_to_color(self.grid["color"])
                case FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION:
                    return self.hex_to_color(self.grid["color"])
                case FontPurpose.LIST_INDEX:
                    return self.hex_to_color(self.currentpage["color"])
                case FontPurpose.LIST_TOTAL:
                    return self.hex_to_color(self.total["color"])
                case _:
                    return self.hex_to_color(self.grid["color"])
        except Exception as e:
            PyUiLogger.get_logger().error(f"text_color error occurred: {e}")
            return self.hex_to_color("#808080")
      
    def text_color_selected(self, font_purpose : FontPurpose):
        try:
            match font_purpose:
                case FontPurpose.GRID_ONE_ROW:
                    return self.hex_to_color(self.grid["selectedcolor"])
                case FontPurpose.GRID_MULTI_ROW:
                    return self.hex_to_color(self.grid["selectedcolor"])
                case FontPurpose.LIST:
                    return self.hex_to_color(self.grid["selectedcolor"])
                case FontPurpose.DESCRIPTIVE_LIST_TITLE:
                    return self.hex_to_color(self.grid["selectedcolor"])
                case FontPurpose.MESSAGE:
                    return self.hex_to_color(self.grid["selectedcolor"])
                case FontPurpose.DESCRIPTIVE_LIST_DESCRIPTION:
                    return self.hex_to_color(self.grid["selectedcolor"])
                case FontPurpose.LIST_INDEX:
                    return self.hex_to_color(self.currentpage["selectedcolor"])
                case FontPurpose.LIST_TOTAL:
                    return self.hex_to_color(self.total["color"])
                case FontPurpose.ON_SCREEN_KEYBOARD:
                    return self.hex_to_color(self.grid["selectedcolor"])
                case _:
                    return self.hex_to_color(self.grid["selectedcolor"])
        except Exception as e:
            PyUiLogger.get_logger().error(f"text_color error occurred: {e}")
            return self.text_color(font_purpose)

    def hex_to_color(self,hex_string):
        hex_string = hex_string.lstrip('#')
        if len(hex_string) != 6:
            raise ValueError("Hex string must be in the format '#RRGGBB'")
        R = int(hex_string[0:2], 16)
        G = int(hex_string[2:4], 16)
        B = int(hex_string[4:6], 16)
        return (R, G, B)

    def get_descriptive_list_icon_offset_x(self):
        return getattr(self, "showBottomBar", None)

    def get_descriptive_list_icon_offset_y(self):
        return getattr(self, "descriptiveListIconOffsetY", 10)
    
    def get_descriptive_list_text_offset_y(self):
        return getattr(self, "descriptiveListTextOffsetY", 15)
    
    def get_descriptive_list_text_from_icon_offset(self):
        return getattr(self, "descriptiveListTextFromIconOffset", 20)
    
    def get_grid_multirow_text_offset_y(self):
        return getattr(self, "gridMultirowTextOffsetY", -25)

    def get_grid_bg(self, rows, cols):
        if(rows > 1):
            #TODO better handle this dynamically
            return self._grid_4_x_2_selected_bg()
        else:
            return None
        
    def get_view_type_for_main_menu(self):
        view_type_str = getattr(self, "mainMenuViewType", "GRID_VIEW")
        view_type = getattr(ViewType, view_type_str, ViewType.GRID_VIEW)
        return view_type
            
    def get_view_type_for_system_select_menu(self):
        view_type_str = getattr(self, "systemSelectViewType", "GRID_VIEW")
        view_type = getattr(ViewType, view_type_str, ViewType.GRID_VIEW)
        return view_type
            
    def get_view_type_for_app_menu(self):
        view_type_str = getattr(self, "appMenuViewType", "DESCRIPTIVE_LIST_VIEW")
        view_type = getattr(ViewType, view_type_str, ViewType.DESCRIPTIVE_LIST_VIEW)
        return view_type
    
    def get_game_system_select_col_count(self):
        return getattr(self, "gameSystemSelectColCount", 4)
    
    def get_game_system_select_row_count(self):
        return getattr(self, "gameSystemSelectRowCount", 2)
    
    @property
    def pop_menu_x_offset(self):
        return getattr(self, "popupMenuXOffsetPercent", 0)/100
    
    @property
    def pop_menu_y_offset(self):
        return getattr(self, "popupMenuYOffsetPercent", 0)/100
        
    @property
    def pop_menu_add_top_bar_height_to_y_offset(self):
        return getattr(self, "addTopBarHeightToYOffset", True)
        
    @property
    def pop_menu_text_padding(self):
        return getattr(self, "popupMenuTextPad", 20)

    @property
    def popup_menu_cols(self):
        return getattr(self, "popupMenuCols", 4)

    @property
    def popup_menu_rows(self):
        return getattr(self, "popupMenuRows", 1)
    
    @property
    def rom_image_width(self):
        return 294 #TODO make percentage of device

    @property
    def rom_image_height(self):
        if(self.show_bottom_bar) :
           return 300  #TODO make percentage of device
        else:
            return 340  #TODO make percentage of device

    @property
    def text_and_image_list_view_mode(self):
        return getattr(self, "textAndImageListViewMode", "TEXT_LEFT_IMAGE_RIGHT")
    
    @property
    def scroll_rom_selection_text(self):
        return getattr(self, "scrollRomSelectionText", True)
