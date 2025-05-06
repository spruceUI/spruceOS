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
        padding = 10
        self.top_bar_w, self.top_bar_h = self.display.render_image(top_bar_bg,0,0)
        battery_text_w, battery_text_h = self.display.render_text(str(battery_percent),self.device.screen_width - padding*2, int(padding*1.25),  self.theme.text_color(FontPurpose.BATTERY_PERCENT), FontPurpose.BATTERY_PERCENT, RenderMode.TOP_RIGHT_ALIGNED)
        battery_icon_x = self.device.screen_width - battery_text_w - (padding*3)
        battery_icon_w, battery_icon_h = self.display.render_image(
            battery_icon ,battery_icon_x,padding,RenderMode.TOP_RIGHT_ALIGNED)
        wifi_icon_x = self.device.screen_width - battery_icon_w - battery_text_w - (padding*4)
        self.display.render_image(wifi_icon,wifi_icon_x,padding, RenderMode.TOP_RIGHT_ALIGNED)
        self.display.render_text_centered(title,int(self.device.screen_width/2), 10, self.theme.text_color(FontPurpose.TOP_BAR_TEXT), FontPurpose.TOP_BAR_TEXT)
        
    def get_top_bar_height(self):
        return self.top_bar_h