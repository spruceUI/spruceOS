from display.x_render_option import XRenderOption
from display.y_render_option import YRenderOption

class RenderMode():
    def __init__(self, x_mode : XRenderOption, y_mode: YRenderOption):
        self._x_mode = x_mode
        self._y_mode = y_mode

    @property
    def x_mode(self):
        return self._x_mode

    @property
    def y_mode(self):
        return self._y_mode
    
RenderMode.TOP_LEFT_ALIGNED = RenderMode(XRenderOption.LEFT, YRenderOption.TOP)
RenderMode.TOP_RIGHT_ALIGNED = RenderMode(XRenderOption.RIGHT, YRenderOption.TOP)
RenderMode.TOP_CENTER_ALIGNED = RenderMode(XRenderOption.CENTER, YRenderOption.TOP)

RenderMode.MIDDLE_LEFT_ALIGNED = RenderMode(XRenderOption.LEFT, YRenderOption.CENTER)
RenderMode.MIDDLE_RIGHT_ALIGNED = RenderMode(XRenderOption.RIGHT, YRenderOption.CENTER)
RenderMode.MIDDLE_CENTER_ALIGNED = RenderMode(XRenderOption.CENTER, YRenderOption.CENTER)

RenderMode.BOTTOM_LEFT_ALIGNED = RenderMode(XRenderOption.LEFT, YRenderOption.BOTTOM)
RenderMode.BOTTOM_RIGHT_ALIGNED = RenderMode(XRenderOption.RIGHT, YRenderOption.BOTTOM)
RenderMode.BOTTOM_CENTER_ALIGNED = RenderMode(XRenderOption.CENTER, YRenderOption.BOTTOM)
