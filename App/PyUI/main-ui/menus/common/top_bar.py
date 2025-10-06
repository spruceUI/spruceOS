from datetime import datetime
import time
import traceback
from devices.device import Device
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from themes.theme import Theme
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig


class TopBar:
    def __init__(self):
        self.title = ""
        self.volume_changed_time = time.time()
        self.volume = 0
        self.selected_tab = "Games"
        
    def render_top_bar(self, title, hide_top_bar_icons = False) :
        if(Theme.skip_main_menu()):
            self.render_top_bar_menu_skipped(title, hide_top_bar_icons)
        else:
            self.render_top_bar_menu_not_skipped(title, hide_top_bar_icons)

    def render_top_bar_menu_skipped(self, title, hide_top_bar_icons = False) :
        from display.display import Display
        top_bar_bg = Theme.get_title_bar_bg()
        self.top_bar_w, self.top_bar_h = Display.render_image(top_bar_bg,0,0)
        center_of_bar = self.top_bar_h //2

        x_offset = Theme.get_top_bar_initial_x_offset()

        games_color = Theme.text_color_selected(FontPurpose.GRID_ONE_ROW) if "Games" == self.selected_tab else Theme.text_color(FontPurpose.GRID_ONE_ROW)
        apps_color = Theme.text_color_selected(FontPurpose.GRID_ONE_ROW) if "Apps" == self.selected_tab else Theme.text_color(FontPurpose.GRID_ONE_ROW)
        settings_color = Theme.text_color_selected(FontPurpose.GRID_ONE_ROW) if "Settings" == self.selected_tab else Theme.text_color(FontPurpose.GRID_ONE_ROW)
        
        text_padding = 20
        w, h = Display.render_text("Games",x_offset, center_of_bar,  games_color, FontPurpose.GRID_ONE_ROW, RenderMode.MIDDLE_LEFT_ALIGNED)
        x_offset += w +text_padding
        w, h = Display.render_text("Apps",x_offset, center_of_bar,  apps_color, FontPurpose.GRID_ONE_ROW, RenderMode.MIDDLE_LEFT_ALIGNED)
        x_offset += w +text_padding
        w, h = Display.render_text("Settings",x_offset, center_of_bar,  settings_color, FontPurpose.GRID_ONE_ROW, RenderMode.MIDDLE_LEFT_ALIGNED)
        x_offset += w +text_padding

        battery_percent = Device.get_battery_percent()
        charging = Device.get_charge_status()
        battery_icon = Theme.get_battery_icon(charging,battery_percent)
        img_padding = 10

        #Battery Text
        x_offset = Device.screen_width() - img_padding
        w, h = Display.render_text(str(battery_percent)+"%",x_offset, center_of_bar,  Theme.text_color(FontPurpose.BATTERY_PERCENT), FontPurpose.BATTERY_PERCENT, RenderMode.MIDDLE_RIGHT_ALIGNED)
        x_offset = x_offset - w - img_padding
        #Battery Icon
        w, h = Display.render_image(
            battery_icon ,x_offset,center_of_bar,RenderMode.MIDDLE_RIGHT_ALIGNED)
        x_offset = x_offset - w - img_padding

        #Wifi
        if(Device.supports_wifi()):
            wifi_status = Device.get_wifi_status()
            wifi_icon = Theme.get_wifi_icon(wifi_status)
            w, h = Display.render_image(wifi_icon,x_offset,center_of_bar, RenderMode.MIDDLE_RIGHT_ALIGNED)
            x_offset = x_offset - w - img_padding
 
        #Volume
        if(time.time() - self.volume_changed_time < 3 and Device.supports_volume()):
            Display.render_image(Theme.get_volume_indicator(self.volume),x_offset,center_of_bar, RenderMode.MIDDLE_RIGHT_ALIGNED)

    def render_top_bar_menu_not_skipped(self, title, hide_top_bar_icons = False) :
        from display.display import Display
        self.title = title
        top_bar_bg = Theme.get_title_bar_bg()
        battery_percent = Device.get_battery_percent()
        charging = Device.get_charge_status()
        battery_icon = Theme.get_battery_icon(charging,battery_percent)
        #TODO Improve padding to not just be 10
        self.top_bar_w, self.top_bar_h = Display.render_image(top_bar_bg,0,0)
        if(Theme.show_top_bar_text()):
            text_w, text_h = Display.get_text_dimensions(FontPurpose.TOP_BAR_TEXT)
            self.top_bar_w = max(self.top_bar_w, text_w)
            self.top_bar_h = max(self.top_bar_h, text_h)

        if(Device.supports_wifi()):
            wifi_status = Device.get_wifi_status()
            wifi_icon = Theme.get_wifi_icon(wifi_status)
            wifi_w, wifi_h = Display.get_image_dimensions(wifi_icon)
            self.top_bar_w = max(self.top_bar_w, wifi_w)
            self.top_bar_h = max(self.top_bar_h, wifi_h)

        battery_w, battery_h = Display.get_image_dimensions(battery_icon)
        self.top_bar_w = max(self.top_bar_w, battery_w)
        self.top_bar_h = max(self.top_bar_h, battery_h)
        
        padding = 10
        center_of_bar = self.top_bar_h //2

        #TODO Allow specifying which side which icon is on    
        if(not hide_top_bar_icons):
            #Battery Text
            x_offset = Device.screen_width() - padding*2
            w, h = Display.render_text(str(battery_percent),x_offset, center_of_bar,  Theme.text_color(FontPurpose.BATTERY_PERCENT), FontPurpose.BATTERY_PERCENT, RenderMode.MIDDLE_RIGHT_ALIGNED)
            x_offset = x_offset - w - padding
            #Battery Icon
            w, h = Display.render_image(
                battery_icon ,x_offset,center_of_bar,RenderMode.MIDDLE_RIGHT_ALIGNED)
            x_offset = x_offset - w - padding
            if(Device.supports_wifi()):
                #Wifi
                w, h = Display.render_image(wifi_icon,x_offset,center_of_bar, RenderMode.MIDDLE_RIGHT_ALIGNED)
                x_offset = x_offset - w - padding
                #Volume
            if(time.time() - self.volume_changed_time < 3):
                Display.render_image(Theme.get_volume_indicator(self.volume),x_offset,center_of_bar, RenderMode.MIDDLE_RIGHT_ALIGNED)

            if(PyUiConfig.show_clock()):   
                x_offset = Theme.get_top_bar_initial_x_offset()
                w, h = Display.render_text(str(self.get_current_time_hhmm()),x_offset, center_of_bar,  Theme.text_color(FontPurpose.BATTERY_PERCENT), FontPurpose.BATTERY_PERCENT, RenderMode.MIDDLE_LEFT_ALIGNED)
                x_offset += w +padding

        if(Theme.show_top_bar_text()):
            Display.render_text(title,
                                int(Device.screen_width()/2), 
                                center_of_bar, 
                                Theme.text_color(FontPurpose.TOP_BAR_TEXT), 
                                FontPurpose.TOP_BAR_TEXT, 
                                RenderMode.MIDDLE_CENTER_ALIGNED)
        
    #TODO make this part of a user config class w/ options for 12 or 24 hour    
    def get_current_time_hhmm(self):
        if(PyUiConfig.use_24_hour_clock()):
            return datetime.now().strftime("%H:%M")
        elif(PyUiConfig.show_am_pm()):
            return datetime.now().strftime("%I:%M %p") 
        else:
            return datetime.now().strftime("%I:%M") 

    def get_top_bar_height(self):
        return self.top_bar_h
    
    def get_current_title(self):
        return self.title
    
    def volume_changed(self, volume):
        PyUiLogger().get_logger().info(f"Setting volume icon {volume}")
        #volume icon is for every 5 volume
        self.volume = volume // 5
        self.volume_changed_time = time.time()

    def set_selected_tab(self, tab):
        self.selected_tab = tab