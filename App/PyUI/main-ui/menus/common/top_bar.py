import time
import traceback
from devices.device import Device
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from themes.theme import Theme


class TopBar:
    def __init__(self):
        self.title = ""
        self.volume_changed_time = time.time()
        self.volume = Device.get_display_volume()

    def render_top_bar(self, title, hide_top_bar_icons = False) :
        from display.display import Display
        self.title = title
        top_bar_bg = Theme.get_title_bar_bg()
        battery_percent = Device.get_battery_percent()
        charging = Device.get_charge_status()
        wifi_status = Device.get_wifi_status()
        battery_icon = Theme.get_battery_icon(charging,battery_percent)
        wifi_icon = Theme.get_wifi_icon(wifi_status)
        #TODO Improve padding to not just be 10
        self.top_bar_w, self.top_bar_h = Display.render_image(top_bar_bg,0,0)
        if(Theme.show_top_bar_text()):
            text_w, text_h = Display.get_text_dimensions(FontPurpose.TOP_BAR_TEXT)
            self.top_bar_w = max(self.top_bar_w, text_w)
            self.top_bar_h = max(self.top_bar_h, text_h)

        wifi_w, wifi_h = Display.get_image_dimensions(wifi_icon)
        self.top_bar_w = max(self.top_bar_w, wifi_w)
        self.top_bar_h = max(self.top_bar_h, wifi_h)
        battery_w, battery_h = Display.get_image_dimensions(battery_icon)
        self.top_bar_w = max(self.top_bar_w, battery_w)
        self.top_bar_h = max(self.top_bar_h, battery_h)
        
        padding = 10
        center_of_bar = self.top_bar_h //2

        if(not hide_top_bar_icons):
            #Battery Text
            x_offset = Device.screen_width() - padding*2
            battery_text_w, battery_text_h = Display.render_text(str(battery_percent),x_offset, center_of_bar,  Theme.text_color(FontPurpose.BATTERY_PERCENT), FontPurpose.BATTERY_PERCENT, RenderMode.MIDDLE_RIGHT_ALIGNED)
            x_offset = x_offset - battery_text_w - padding
            #Battery Icon
            battery_icon_w, battery_icon_h = Display.render_image(
                battery_icon ,x_offset,center_of_bar,RenderMode.MIDDLE_RIGHT_ALIGNED)
            x_offset = x_offset - battery_icon_w - padding
            #Wifi
            wifi_icon_w, wifi_icon_h = Display.render_image(wifi_icon,x_offset,center_of_bar, RenderMode.MIDDLE_RIGHT_ALIGNED)
            x_offset = x_offset - wifi_icon_w - padding
            #Volume
            if(time.time() - self.volume_changed_time < 3):
                Display.render_image(Theme.get_volume_indicator(self.volume),x_offset,center_of_bar, RenderMode.MIDDLE_RIGHT_ALIGNED)


        if(Theme.show_top_bar_text()):
            Display.render_text(title,int(Device.screen_width()/2), center_of_bar, Theme.text_color(FontPurpose.TOP_BAR_TEXT), FontPurpose.TOP_BAR_TEXT, RenderMode.MIDDLE_CENTER_ALIGNED)
        
    def get_top_bar_height(self):
        return self.top_bar_h
    
    def get_current_title(self):
        return self.title
    
    def volume_changed(self, volume):
        self.volume = volume
        self.volume_changed_time = time.time()