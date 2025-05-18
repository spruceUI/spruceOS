from devices.device import Device
from devices.device_common import DeviceCommon
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from themes.theme import Theme


class BottomBar:
    def __init__(self):
        pass

    def render_bottom_bar(self) :
        from display.display import Display
        if(Theme.show_bottom_bar()):
            bottom_bar_bg = Theme.bottom_bar_bg()
            confirm_icon = Theme.confirm_icon()
            back_icon = Theme.back_icon()
            
            self.bottom_bar_w, self.bottom_bar_h = Display.render_image(bottom_bar_bg,0,Device.screen_height(),render_mode=RenderMode.BOTTOM_LEFT_ALIGNED)
            
            # TODO don't hard code these
            padding = 5 
            bottom_icons_y = Device.screen_height() - padding

            confirm_icon_x = padding
            confirm_icon_w, confirm_icon_h = Display.render_image(confirm_icon,confirm_icon_x, bottom_icons_y, RenderMode.BOTTOM_LEFT_ALIGNED)
            
            confirm_text_x = padding + confirm_icon_w + padding
            confirm_text_y = bottom_icons_y - confirm_icon_h//2
            confirm_text_w, confirm_text_h = Display.render_text(Theme.confirm_text(),
                                                                      confirm_text_x,
                                                                      confirm_text_y, 
                                                                      Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_TITLE), 
                                                                      FontPurpose.DESCRIPTIVE_LIST_TITLE, 
                                                                      RenderMode.MIDDLE_LEFT_ALIGNED)

            back_icon_x = padding + confirm_icon_w + padding + confirm_text_w + padding
            back_icon_w, back_icon_h = Display.render_image(back_icon,back_icon_x, bottom_icons_y, RenderMode.BOTTOM_LEFT_ALIGNED)
            
            back_text_x = padding + confirm_icon_w + padding + confirm_text_w + padding + back_icon_w + padding
            back_text_y = bottom_icons_y - back_icon_h//2
            back_text_w, back_text_h = Display.render_text(Theme.back_text(),
                                                                back_text_x,
                                                                back_text_y, 
                                                                Theme.text_color(FontPurpose.DESCRIPTIVE_LIST_TITLE), 
                                                                FontPurpose.DESCRIPTIVE_LIST_TITLE, 
                                                                RenderMode.MIDDLE_LEFT_ALIGNED)
        else:
            self.bottom_bar_h = 0

    def get_bottom_bar_height(self):
        return self.bottom_bar_h