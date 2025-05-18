from devices.device import Device
from display.font_purpose import FontPurpose
from display.loaded_font import LoadedFont
from display.render_mode import RenderMode
from display.x_render_option import XRenderOption
from display.y_render_option import YRenderOption
from menus.common.bottom_bar import BottomBar
from menus.common.top_bar import TopBar
import sdl2
import sdl2.ext
import sdl2.sdlttf
from themes.theme import Theme
from utils.logger import PyUiLogger

class Display:
    debug = False
    renderer = None
    fonts = {}
    bg_canvas = None
    render_canvas = None
    bg_path = ""
    top_bar = None
    bottom_bar = None
    window = None
    background_texture = None
    screen = None

    @classmethod
    def init(cls):
        cls._init_display()
        cls.init_fonts()
        cls.render_canvas = sdl2.SDL_CreateTexture(
            cls.renderer.renderer,
            sdl2.SDL_PIXELFORMAT_ARGB8888,
            sdl2.SDL_TEXTUREACCESS_TARGET,
            Device.screen_width(),
            Device.screen_height()
        )
        PyUiLogger.get_logger().info(f"sdl2.SDL_GetError() : {sdl2.SDL_GetError()}")
        sdl2.SDL_SetRenderTarget(cls.renderer.renderer, cls.render_canvas)
        PyUiLogger.get_logger().info(f"sdl2.SDL_GetError() : {sdl2.SDL_GetError()}")
        cls._check_for_bg_change()
        cls.top_bar = TopBar()
        cls.bottom_bar = BottomBar()
        cls.clear("init")
        cls.present()

    @classmethod
    def init_fonts(cls):
        cls.fonts = {
            purpose: cls._load_font(purpose)
            for purpose in FontPurpose
        }


    @classmethod
    def _init_display(cls):
        sdl2.ext.init(controller=True)
        sdl2.SDL_InitSubSystem(sdl2.SDL_INIT_GAMECONTROLLER)

        display_mode = sdl2.SDL_DisplayMode()
        if sdl2.SDL_GetCurrentDisplayMode(0, display_mode) != 0:
            PyUiLogger.get_logger().error("Failed to get display mode, using fallback 640x480")
            width, height = Device.screen_width(), Device.screen_height()
        else:
            width, height = display_mode.w, display_mode.h
            PyUiLogger.get_logger().info(f"Display size: {width}x{height}")

        cls.window = sdl2.ext.Window("Minimal SDL2 GUI", size=(width, height), flags=sdl2.SDL_WINDOW_FULLSCREEN)
        cls.window.show()

        sdl2.SDL_SetHint(sdl2.SDL_HINT_RENDER_SCALE_QUALITY, b"2")
        cls.renderer = sdl2.ext.Renderer(cls.window, flags=sdl2.SDL_RENDERER_ACCELERATED)

    @classmethod
    def deinit_display(cls):
        if cls.renderer is not None:
            sdl2.SDL_DestroyRenderer(cls.renderer.sdlrenderer)
            cls.renderer = None
        if cls.window is not None:
            sdl2.SDL_DestroyWindow(cls.window.window)
            cls.window = None
        cls.deinit_fonts()
        cls._unload_bg_texture()
        sdl2.SDL_QuitSubSystem(sdl2.SDL_INIT_VIDEO)

    @classmethod
    def deinit_fonts(cls):
        for loaded_font in cls.fonts.values():
            sdl2.sdlttf.TTF_CloseFont(loaded_font.font)
        cls.fonts.clear()

    @classmethod
    def reinitialize(cls):
        cls.deinit_display()
        cls._unload_bg_texture()
        cls._init_display()
        cls.init_fonts()
        cls._load_bg_texture()
        cls.clear("reinitialize")
        cls.present()


    @classmethod
    def _unload_bg_texture(cls):
        if cls.background_texture:
            sdl2.SDL_DestroyTexture(cls.background_texture)
            cls.background_texture = None
            PyUiLogger.get_logger().debug("Destroying bg texture")

    @classmethod
    def _load_bg_texture(cls):
        cls.bg_path = Theme.background()
        surface = sdl2.sdlimage.IMG_Load(cls.bg_path.encode('utf-8'))
        if not surface:
            PyUiLogger.get_logger().error(f"Failed to load image: {cls.bg_path}")
            return

        cls.background_texture = sdl2.SDL_CreateTextureFromSurface(cls.renderer.renderer, surface)
        sdl2.SDL_FreeSurface(surface)

        if not cls.background_texture:
            PyUiLogger.get_logger().error("Failed to create texture from surface")

    @classmethod
    def _check_for_bg_change(cls):
        new_bg_path = Theme.background()
        if cls.bg_path != new_bg_path:
            cls._unload_bg_texture()
            cls._load_bg_texture()

    @classmethod
    def _load_font(cls, font_purpose):
        if sdl2.sdlttf.TTF_Init() == -1:
            raise RuntimeError("Failed to initialize SDL_ttf")

        font_path = Theme.get_font(font_purpose)
        font_size = Theme.get_font_size(font_purpose)

        font = sdl2.sdlttf.TTF_OpenFont(font_path.encode("utf-8"), font_size)
        if not font:
            raise RuntimeError(
                f"Could not load font {font_path} : {sdl2.sdlttf.TTF_GetError().decode('utf-8')}"
            )

        line_height = sdl2.sdlttf.TTF_FontHeight(font)
        return LoadedFont(font, line_height)



    @classmethod
    def lock_current_image_as_bg(cls):
        cls.bg_canvas = cls.render_canvas
        cls.render_canvas = sdl2.SDL_CreateTexture(
            cls.renderer.renderer,
            sdl2.SDL_PIXELFORMAT_ARGB8888,
            sdl2.SDL_TEXTUREACCESS_TARGET,
            Device.screen_width(),
            Device.screen_height()
        )
        sdl2.SDL_SetRenderTarget(cls.renderer.renderer, cls.render_canvas)
        sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, cls.bg_canvas, None, None)

    @classmethod
    def unlock_current_image_as_bg(cls):
        if cls.bg_canvas:
            sdl2.SDL_DestroyTexture(cls.bg_canvas)
            cls.bg_canvas = None

    @classmethod
    def clear(cls, screen):
        cls.screen = screen
        cls._check_for_bg_change()

        if cls.bg_canvas is not None:
            sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, cls.bg_canvas, None, None)
        elif cls.background_texture is not None:
            sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, cls.background_texture, None, None)

        if not Theme.render_top_and_bottom_bar_last():
            cls.top_bar.render_top_bar(cls.screen)
            cls.bottom_bar.render_bottom_bar()

    @staticmethod
    def _calculate_scaled_width_and_height(orig_w, orig_h, target_width, target_height):
        # Maintain aspect ratio
        if target_width and target_height:
            scale = min(target_width / orig_w, target_height / orig_h)
            render_w = int(orig_w * scale)
            render_h = int(orig_h * scale)
        elif target_width:
            scale = target_width / orig_w
            render_w = int(orig_w * scale)
            render_h = orig_h
        elif target_height:
            render_w = orig_w
            scale = target_height / orig_h
            render_h = int(orig_h * scale)
        else:
            render_w = orig_w
            render_h = orig_h

        return int(render_w), int(render_h)

    @classmethod
    def _log(cls, msg):
        if cls.debug:
            PyUiLogger.get_logger().info(msg)

    @classmethod
    def _render_surface_texture(cls, x, y, texture, surface, render_mode: RenderMode, scale_width=None, scale_height=None, debug="",
                                crop_w=None, crop_h=None):
        render_w, render_h = cls._calculate_scaled_width_and_height(surface.contents.w, surface.contents.h, scale_width, scale_height)

        # Adjust position based on render mode
        adj_x = x
        adj_y = y
        
        if XRenderOption.CENTER == render_mode.x_mode:
            adj_x = x - render_w // 2
        elif XRenderOption.RIGHT == render_mode.x_mode:
            adj_x = x - render_w

        if YRenderOption.CENTER == render_mode.y_mode:
            adj_y = y - render_h // 2
        elif YRenderOption.BOTTOM == render_mode.y_mode:
            adj_y = y - render_h

        adj_x = int(adj_x)
        adj_y = int(adj_y)

        if crop_w is None and crop_h is None:            
            rect = sdl2.SDL_Rect(adj_x, adj_y, render_w, render_h)
            cls._log(f"Rendered {debug} at {adj_x}, {adj_y} with dimensions {render_w}x{render_h}")
            sdl2.SDL_RenderCopy(cls.renderer.renderer, texture, None, rect)
        else:
            if crop_w is None or crop_w > surface.contents.w:
                crop_w = surface.contents.w
            if crop_h is None or crop_h > surface.contents.h:
                crop_h = surface.contents.h

            src_rect = sdl2.SDL_Rect(0, 0, crop_w, crop_h)
            dst_rect = sdl2.SDL_Rect(adj_x, adj_y, int(crop_w), int(crop_h))
            sdl2.SDL_RenderCopy(cls.renderer.renderer, texture, src_rect, dst_rect)

        sdl2.SDL_DestroyTexture(texture)
        sdl2.SDL_FreeSurface(surface)

        return render_w, render_h

    @classmethod
    def render_text(cls, text, x, y, color, purpose: FontPurpose, render_mode=RenderMode.TOP_LEFT_ALIGNED,
                    crop_w=None, crop_h=None):
        sdl_color = sdl2.SDL_Color(color[0], color[1], color[2])
        surface = sdl2.sdlttf.TTF_RenderUTF8_Blended(cls.fonts[purpose].font, text.encode('utf-8'), sdl_color)
        if not surface:
            PyUiLogger.get_logger().error(f"Failed to render text surface for {text}: {sdl2.sdlttf.TTF_GetError().decode('utf-8')}")
            return 0, 0

        texture = sdl2.SDL_CreateTextureFromSurface(cls.renderer.renderer, surface)
        if not texture:
            sdl2.SDL_FreeSurface(surface)
            PyUiLogger.get_logger().error(f"Failed to create texture from surface {text}: {sdl2.sdlttf.TTF_GetError().decode('utf-8')}")
            return 0, 0

        return cls._render_surface_texture(x, y, texture, surface, render_mode, debug=text, crop_w=crop_w, crop_h=crop_h)

    @classmethod
    def render_text_centered(cls, text, x, y, color, purpose: FontPurpose):
        return cls.render_text(text, x, y, color, purpose, RenderMode.TOP_CENTER_ALIGNED)

    @classmethod
    def render_image(cls, image_path: str, x: int, y: int, render_mode=RenderMode.TOP_LEFT_ALIGNED, target_width=None, target_height=None):
        if(image_path is None):
            return 0, 0
        surface = sdl2.sdlimage.IMG_Load(image_path.encode('utf-8'))
        if not surface:
            PyUiLogger.get_logger().error(f"Failed to load image: {image_path}")
            return 0, 0

        texture = sdl2.SDL_CreateTextureFromSurface(cls.renderer.renderer, surface)
        if not texture:
            sdl2.SDL_FreeSurface(surface)
            PyUiLogger.get_logger().error("Failed to create texture from surface")
            return 0, 0

        sdl2.SDL_SetTextureBlendMode(texture, sdl2.SDL_BLENDMODE_BLEND)
        return cls._render_surface_texture(x, y, texture, surface, render_mode, target_width, target_height, debug=image_path)

    @classmethod
    def render_image_centered(cls, image_path: str, x: int, y: int, target_width=None, target_height=None):
        return cls.render_image(image_path, x, y, RenderMode.TOP_CENTER_ALIGNED, target_width, target_height)

    @classmethod
    def render_box(cls, color, x, y, w, h):
        sdl2.SDL_SetRenderDrawColor(cls.renderer.renderer, color[0], color[1], color[2], 255)
        rect = sdl2.SDL_Rect(x, y, w, h)
        sdl2.SDL_RenderFillRect(cls.renderer.renderer, rect)


    @classmethod
    def get_line_height(cls, purpose: FontPurpose):
        return cls.fonts[purpose].line_height

    @classmethod
    def scale_texture_to_fit(cls, src_texture: sdl2.SDL_Texture, target_width: int, target_height: int) -> sdl2.SDL_Texture:
        width = sdl2.c_int()
        height = sdl2.c_int()
        sdl2.SDL_QueryTexture(src_texture, None, None, width, height)

        src_w = width.value
        src_h = height.value

        scale = min(target_width / src_w, target_height / src_h)
        new_width = int(src_w * scale)
        new_height = int(src_h * scale)

        offset_x = (target_width - new_width) // 2
        offset_y = (target_height - new_height) // 2

        scaled_texture = sdl2.SDL_CreateTexture(
            cls.renderer.sdlrenderer,
            sdl2.SDL_PIXELFORMAT_ARGB8888,
            sdl2.SDL_TEXTUREACCESS_TARGET,
            target_width,
            target_height
        )

        if not scaled_texture:
            raise RuntimeError("Failed to create scaled texture")

        old_target = sdl2.SDL_GetRenderTarget(cls.renderer.sdlrenderer)

        sdl2.SDL_SetTextureBlendMode(src_texture, sdl2.SDL_BLENDMODE_BLEND)
        sdl2.SDL_SetTextureBlendMode(scaled_texture, sdl2.SDL_BLENDMODE_BLEND)

        sdl2.SDL_SetRenderTarget(cls.renderer.sdlrenderer, scaled_texture)
        sdl2.SDL_SetRenderDrawColor(cls.renderer.sdlrenderer, 0, 0, 0, 0)
        sdl2.SDL_RenderClear(cls.renderer.sdlrenderer)

        dest_rect = sdl2.SDL_Rect(offset_x, offset_y, new_width, new_height)
        sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, src_texture, None, dest_rect)

        sdl2.SDL_SetRenderTarget(cls.renderer.sdlrenderer, old_target)
        return scaled_texture

    @classmethod
    def present(cls):
        if Theme.render_top_and_bottom_bar_last():
            cls.top_bar.render_top_bar(cls.screen)
            cls.bottom_bar.render_bottom_bar()

        sdl2.SDL_SetRenderTarget(cls.renderer.renderer, None)

        if Device.should_scale_screen():
            scaled_canvas = cls.scale_texture_to_fit(cls.render_canvas, Device.output_screen_width, Device.output_screen_height)
            sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, scaled_canvas, None, None)
            sdl2.SDL_DestroyTexture(scaled_canvas)
        else:
            sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, cls.render_canvas, None, None)

        sdl2.SDL_SetRenderTarget(cls.renderer.renderer, cls.render_canvas)
        cls.renderer.present()

    @classmethod
    def get_top_bar_height(cls):
        return 0 if Theme.ignore_top_and_bottom_bar_for_layout() else cls.top_bar.get_top_bar_height()

    @classmethod
    def get_bottom_bar_height(cls):
        return 0 if Theme.ignore_top_and_bottom_bar_for_layout() else cls.bottom_bar.get_bottom_bar_height()

    @classmethod
    def get_usable_screen_height(cls):
        return Device.screen_height() - cls.get_bottom_bar_height() - cls.get_top_bar_height()

    @classmethod
    def get_center_of_usable_screen_height(cls):
        return ((Device.screen_height() - cls.get_bottom_bar_height() - cls.get_top_bar_height()) // 2) + cls.get_top_bar_height()

    @classmethod
    def get_image_dimensions(cls, img):
        if(img is None):
            return 0, 0
        
        surface = sdl2.sdlimage.IMG_Load(img.encode('utf-8'))
        if not surface:
            return 0, 0
        width, height = surface.contents.w, surface.contents.h
        sdl2.SDL_FreeSurface(surface)
        return width, height

    @classmethod
    def get_text_dimensions(cls, purpose, text="A"):
        sdl_color = sdl2.SDL_Color(0, 0, 0)
        surface = sdl2.sdlttf.TTF_RenderUTF8_Blended(cls.fonts[purpose].font, text.encode('utf-8'), sdl_color)
        if not surface:
            return 0, 0
        width, height = surface.contents.w, surface.contents.h
        sdl2.SDL_FreeSurface(surface)
        return width, height

    @classmethod
    def add_index_text(cls, index, total):
        if(Theme.show_index_text()):
            y_padding = max(5, cls.get_bottom_bar_height() // 4)
            y_value = Device.screen_height() - y_padding
            x_padding = 10

            total_text_x = Device.screen_width() - x_padding
            total_text_w, _ = cls.render_text(
                str(total),
                total_text_x,
                y_value,
                Theme.text_color(FontPurpose.LIST_TOTAL),
                FontPurpose.LIST_TOTAL,
                RenderMode.BOTTOM_RIGHT_ALIGNED
            )

            index_text_x = Device.screen_width() - x_padding - total_text_w
            cls.render_text(
                str(index) + "/",
                index_text_x,
                y_value,
                Theme.text_color(FontPurpose.LIST_INDEX),
                FontPurpose.LIST_INDEX,
                RenderMode.BOTTOM_RIGHT_ALIGNED
            )

    @classmethod
    def get_current_top_bar_title(cls):
        return cls.top_bar.get_current_title()

