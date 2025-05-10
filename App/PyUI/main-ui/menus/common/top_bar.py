from devices.device import Device
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from themes.theme import Theme


class TopBar:
    def __init__(self, display, device: Device, theme: Theme):
        self.display= display
        self.device : Device= device
        self.theme : Theme= theme


    def render_top_bar(self, title) :
        top_bar_bg = self.theme.get_title_bar_bg
        battery_percent = self.device.get_battery_percent()
        charging = self.device.get_charge_status()
        wifi_status = self.device.get_wifi_status()
        battery_icon = self.theme.get_battery_icon(charging,battery_percent)
        wifi_icon = self.theme.get_wifi_icon(wifi_status)
        #TODO Improve padding to not just be 10
        self.top_bar_w, self.top_bar_h = self.display.render_image(top_bar_bg,0,0)
        text_w, text_h = self.display.get_text_dimensions(FontPurpose.TOP_BAR_TEXT)
        self.top_bar_w = max(self.top_bar_w, text_w)
        self.top_bar_h = max(self.top_bar_h, text_h)

        wifi_w, wifi_h = self.display.get_image_dimensions(wifi_icon)
        self.top_bar_w = max(self.top_bar_w, wifi_w)
        self.top_bar_h = max(self.top_bar_h, wifi_h)
        battery_w, battery_h = self.display.get_image_dimensions(battery_icon)
        self.top_bar_w = max(self.top_bar_w, battery_w)
        self.top_bar_h = max(self.top_bar_h, battery_h)

        
        padding = 10
        center_of_bar = self.top_bar_h //2
        battery_text_w, battery_text_h = self.display.render_text(str(battery_percent),self.device.screen_width - padding*2, center_of_bar,  self.theme.text_color(FontPurpose.BATTERY_PERCENT), FontPurpose.BATTERY_PERCENT, RenderMode.MIDDLE_RIGHT_ALIGNED)
        battery_icon_x = self.device.screen_width - battery_text_w - (padding*3)
        battery_icon_w, battery_icon_h = self.display.render_image(
            battery_icon ,battery_icon_x,center_of_bar,RenderMode.MIDDLE_RIGHT_ALIGNED)
        wifi_icon_x = self.device.screen_width - battery_icon_w - battery_text_w - (padding*4)
        self.display.render_image(wifi_icon,wifi_icon_x,center_of_bar, RenderMode.MIDDLE_RIGHT_ALIGNED)
        self.display.render_text(title,int(self.device.screen_width/2), center_of_bar, self.theme.text_color(FontPurpose.TOP_BAR_TEXT), FontPurpose.TOP_BAR_TEXT, RenderMode.MIDDLE_CENTER_ALIGNED)
        
    def get_top_bar_height(self):
        return self.top_bar_h