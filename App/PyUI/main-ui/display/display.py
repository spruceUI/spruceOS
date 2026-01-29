from dataclasses import dataclass
import os
import time
from devices.device import Device
from display.font_purpose import FontPurpose
from display.loaded_font import LoadedFont
from display.render_mode import RenderMode
from display.resize_type import ResizeType
from display.x_render_option import XRenderOption
from display.y_render_option import YRenderOption
from menus.common.bottom_bar import BottomBar
from menus.common.top_bar import TopBar
import sdl2
import sdl2.ext
import sdl2.sdlttf
from themes.theme import Theme
from utils.logger import PyUiLogger
import ctypes
import traceback

from utils.time_logger import log_timing

@dataclass
class CachedImageTexture:
    def __init__(self, surface, texture):
        self.surface = surface
        self.texture = texture

class ImageTextureCache:
    def __init__(self):
        self.cache = {} 

    def get_texture(self, texture_id) -> CachedImageTexture:
        return self.cache.get(texture_id)

    def add_texture(self, texture_id, surface, texture):
        self.cache[texture_id] = CachedImageTexture(surface,texture)
        return True
    
    def clear_cache(self):
        for entry in self.cache.values():
            sdl2.SDL_DestroyTexture(entry.texture)
            sdl2.SDL_FreeSurface(entry.surface)
        self.cache.clear()

    def size(self):
        return len(self.cache)

@dataclass(frozen=True)
class TextTextureKey:
    texture_id : str
    font : object
    color : tuple

@dataclass
class CachedTextTexture:
    def __init__(self, surface, texture):
        self.surface = surface
        self.texture = texture

class TextTextureCache:
    def __init__(self):
        self.cache = {} 

    def get_texture(self, texture_id, font, color) -> CachedTextTexture:
        return self.cache.get(TextTextureKey(texture_id, font, color))

    def add_texture(self, texture_id, font, color, surface, texture):
        self.cache[TextTextureKey(texture_id, font, color)] = CachedTextTexture(surface,texture)
        return True
    
    def clear_cache(self):
        for entry in self.cache.values():
            sdl2.SDL_DestroyTexture(entry.texture)
            sdl2.SDL_FreeSurface(entry.surface)
        self.cache.clear()
        
class Display:
    debug = False
    renderer = None
    fonts = {}
    bg_canvas = None
    render_canvas = None
    bg_path = ""
    top_bar = TopBar()
    bottom_bar = BottomBar()
    window = None
    background_texture = None
    top_bar_text = None
    _image_texture_cache = ImageTextureCache()
    _text_texture_cache = TextTextureCache()
    _problematic_images = set()  # Class-level set to track images that won't load properly
    _problematic_image_keywords = [
        "No such file or directory",
        "Text has zero width",
        "Texture dimensions are limited",
        "Corrupt PNG"
    ]

    @classmethod
    def init(cls):
        cls._init_display()
        #Outside init_fonts as it should only ever be called once
        with log_timing("sdl2.sdlttf.TTF_Init()", PyUiLogger.get_logger()):    
            if sdl2.sdlttf.TTF_Init() == -1:
                raise RuntimeError("Failed to initialize SDL_ttf")
            cls.init_fonts()


        with log_timing("sdl2 create render canvas", PyUiLogger.get_logger()):    
            cls.render_canvas = sdl2.SDL_CreateTexture(
                cls.renderer.renderer,
                sdl2.SDL_PIXELFORMAT_ARGB1555,
                sdl2.SDL_TEXTUREACCESS_TARGET,
                Device.get_device().screen_width(),
                Device.get_device().screen_height()
            )
            cls.log_sdl_error_if_any()

        with log_timing("sdl2.SDL_SetRenderTarget", PyUiLogger.get_logger()):    
            sdl2.SDL_SetRenderTarget(cls.renderer.renderer, cls.render_canvas)
            cls.log_sdl_error_if_any()
        with log_timing("sdl2.SDL_SetRenderDrawBlendMode", PyUiLogger.get_logger()):    
            sdl2.SDL_SetRenderDrawBlendMode(cls.renderer.renderer, sdl2.SDL_BLENDMODE_BLEND)
            cls.log_sdl_error_if_any()

        if(Device.get_device().double_init_sdl_display()):
            Display.deinit_display()
            Display.reinitialize()

        if(Device.get_device().might_require_surface_format_conversion()):
            info = sdl2.SDL_RendererInfo()
            sdl2.SDL_GetRendererInfo(cls.renderer.renderer, info)
            cls.supported_formats = set(info.texture_formats[:info.num_texture_formats])


        with log_timing("restore_bg", PyUiLogger.get_logger()):    
            cls.restore_bg()

        with log_timing("clear", PyUiLogger.get_logger()):    
            cls.clear("", force_top_and_bottom_bar=True)    

        if(False):
            Display.log_sdl_render_drivers()
            Display.log_current_renderer()

        #Debug prints
        if(False):
            scale_x = ctypes.c_float()
            scale_y = ctypes.c_float()
            sdl2.SDL_RenderGetScale(cls.renderer.renderer, ctypes.byref(scale_x), ctypes.byref(scale_y))
            PyUiLogger.get_logger().info(f"Renderer scale: {scale_x.value}, {scale_y.value}")

            window_w = ctypes.c_int()
            window_h = ctypes.c_int()
            drawable_w = ctypes.c_int()
            drawable_h = ctypes.c_int()

            sdl2.SDL_GetWindowSize(cls.window.window, ctypes.byref(window_w), ctypes.byref(window_h))
            sdl2.SDL_GL_GetDrawableSize(cls.window.window, ctypes.byref(drawable_w), ctypes.byref(drawable_h))

            PyUiLogger.get_logger().info(
                f"Window size: {window_w.value}x{window_h.value}, Drawable size: {drawable_w.value}x{drawable_h.value}"
            )

    @classmethod
    def log_sdl_render_drivers(cls):
        # Number of render drivers available
        num_drivers = sdl2.SDL_GetNumRenderDrivers()
        PyUiLogger.get_logger().info(f"SDL found {num_drivers} render drivers:")

        info = sdl2.SDL_RendererInfo()

        for i in range(num_drivers):
            sdl2.SDL_GetRenderDriverInfo(i, ctypes.byref(info))

            PyUiLogger.get_logger().info(f"Driver #{i}: {info.name.decode()}")
            PyUiLogger.get_logger().info(f"  Max texture size: {info.max_texture_width}x{info.max_texture_height}")

            # Log supported flags
            print("  Flags:", end=" ")
            flags = []
            if info.flags & sdl2.SDL_RENDERER_SOFTWARE: flags.append("SOFTWARE")
            if info.flags & sdl2.SDL_RENDERER_ACCELERATED: flags.append("ACCELERATED")
            if info.flags & sdl2.SDL_RENDERER_PRESENTVSYNC: flags.append("VSYNC")
            if info.flags & sdl2.SDL_RENDERER_TARGETTEXTURE: flags.append("TARGETTEXTURE")
            PyUiLogger.get_logger().info(", ".join(flags) if flags else "None")

            # Log supported texture formats
            PyUiLogger.get_logger().info("  Supported texture formats:")
            for j in range(info.num_texture_formats):
                fmt = info.texture_formats[j]
                name = sdl2.SDL_GetPixelFormatName(fmt).decode()
                PyUiLogger.get_logger().info(f"    - {name}")


    @classmethod
    def log_current_renderer(cls):
        info = sdl2.SDL_RendererInfo()
        sdl2.SDL_GetRendererInfo(cls.renderer.renderer, ctypes.byref(info))
        PyUiLogger.get_logger().info(f"SDL selected renderer: {info.name.decode()}")

    @classmethod
    def log_sdl_error_if_any(cls):
        err = sdl2.SDL_GetError()
        if err:  # Only log if not empty
            PyUiLogger.get_logger().info(f"sdl2.SDL_GetError() : {err}")

    @classmethod
    def init_fonts(cls):
        cls.fonts = {
            purpose: cls._load_font(purpose)
            for purpose in FontPurpose
        }


    @classmethod
    def _init_display(cls):
        with log_timing("sdl2.ext.init", PyUiLogger.get_logger()):    
            sdl2.ext.init(controller=False)

        with log_timing("sdl2.SDL_DisplayMode", PyUiLogger.get_logger()):    
            display_mode = sdl2.SDL_DisplayMode()
            if sdl2.SDL_GetCurrentDisplayMode(0, display_mode) != 0:
                PyUiLogger.get_logger().error("Failed to get display mode, using fallback 640x480")
                width, height = Device.get_device().screen_width(), Device.get_device().screen_height()
            else:
                width, height = display_mode.w, display_mode.h
                #PyUiLogger.get_logger().info(f"Display size: {width}x{height}")

        with log_timing("sdl2.ext.Window", PyUiLogger.get_logger()):    
            cls.window = sdl2.ext.Window("Minimal SDL2 GUI", size=(width, height), flags=sdl2.SDL_WINDOW_FULLSCREEN)
            cls.window.show()


        with log_timing("sdl2.ext.Renderer", PyUiLogger.get_logger()):    
            sdl2.SDL_SetHint(sdl2.SDL_HINT_RENDER_SCALE_QUALITY, b"2")
            cls.renderer = sdl2.ext.Renderer(cls.window, flags=sdl2.SDL_RENDERER_ACCELERATED)

    @classmethod
    def deinit_display(cls):
        if cls.render_canvas:
            sdl2.SDL_DestroyTexture(cls.render_canvas)
            cls.render_canvas = None
        if cls.bg_canvas:
            sdl2.SDL_DestroyTexture(cls.bg_canvas)
            cls.bg_canvas = None
        if cls.renderer is not None:
            sdl2.SDL_DestroyRenderer(cls.renderer.sdlrenderer)
            cls.renderer = None
        if cls.window is not None:
            sdl2.SDL_DestroyWindow(cls.window.window)
            cls.window = None
        cls.deinit_fonts()
        cls._unload_bg_texture()
        cls._text_texture_cache.clear_cache()
        cls._image_texture_cache.clear_cache()
        sdl2.SDL_QuitSubSystem(sdl2.SDL_INIT_VIDEO)

    @classmethod
    def clear_text_cache(cls):
        cls._text_texture_cache.clear_cache()
        cls.deinit_fonts()
        cls.init_fonts()

    @classmethod
    def clear_image_cache(cls):
        cls._image_texture_cache.clear_cache()

    @classmethod
    def clear_cache(cls):
        cls.clear_image_cache()
        cls.clear_text_cache()

    @classmethod
    def deinit_fonts(cls):
        for loaded_font in cls.fonts.values():
            sdl2.sdlttf.TTF_CloseFont(loaded_font.font)
        cls.fonts.clear()

    @classmethod
    def reinitialize(cls, bg=None):
        cls.deinit_display()
        cls._unload_bg_texture()
        cls._init_display()
        cls.init_fonts()
        cls.restore_bg(bg)
        cls.clear("")
        cls.present()


    @classmethod
    def _unload_bg_texture(cls):
        if cls.background_texture:
            sdl2.SDL_DestroyTexture(cls.background_texture)
            cls.background_texture = None

    @classmethod
    def restore_bg(cls, bg=None):
        if(bg is not None):
            cls.set_new_bg(bg, is_custom_theme_background=True)
        else:
            cls.set_new_bg(Theme.background(), is_custom_theme_background=False)

    @classmethod
    def set_new_bg(cls, bg_path, is_custom_theme_background, retry=True):
        if(bg_path is not None and bg_path != cls.bg_path):
            cls._unload_bg_texture()
            cls.is_custom_theme_background = is_custom_theme_background
            cls.bg_path = bg_path
            surface = Display.image_load(cls.bg_path)
            if not surface:
                PyUiLogger.get_logger().error(f"Failed to load image: {cls.bg_path}")
                return

            cls.background_texture = sdl2.SDL_CreateTextureFromSurface(cls.renderer.renderer, surface)
            sdl2.SDL_FreeSurface(surface)

            if not cls.background_texture:
                if(retry):
                    PyUiLogger.get_logger().info("Retrying bg texture")
                    cls._text_texture_cache.clear_cache()
                    cls._image_texture_cache.clear_cache()
                    cls.bg_path = None
                    cls.set_new_bg(bg_path, is_custom_theme_background, retry=False)
                else:
                    PyUiLogger.get_logger().error("Failed to create bg texture")

        elif(bg_path is None):
            PyUiLogger.get_logger().error(f"Background path none")

    @classmethod
    def set_page_bg(cls, page_bg):
        background = Theme.background(page_bg)
        if(background is not None and os.path.exists(background)):
            cls.set_new_bg(background, is_custom_theme_background=True)

    @classmethod
    def set_selected_tab(cls, tab):
        cls.top_bar.set_selected_tab(tab)

    @classmethod
    def _load_font(cls, font_purpose):
        font_path = Theme.get_font(font_purpose)
        font_size = Theme.get_font_size(font_purpose)

        font = sdl2.sdlttf.TTF_OpenFont(font_path.encode("utf-8"), font_size)
        if not font:
            raise RuntimeError(
                f"Could not load font {font_path} : {sdl2.sdlttf.TTF_GetError().decode('utf-8')}"
            )

        line_height = sdl2.sdlttf.TTF_FontHeight(font)
        surface = sdl2.sdlttf.TTF_RenderUTF8_Blended(font, "A".encode('utf-8'), sdl2.SDL_Color(0, 0, 0))
        if not surface:
            line_height = 0
        else:
            sdl2.SDL_FreeSurface(surface)

        return LoadedFont(font, line_height, font_path)

    @classmethod
    def lock_current_image(cls):
        PyUiLogger.get_logger().info("Locking current image as background")
        if cls.bg_canvas:
            sdl2.SDL_DestroyTexture(cls.bg_canvas)
            cls.bg_canvas = None
    
        cls.bg_canvas = cls.render_canvas
        cls.render_canvas = sdl2.SDL_CreateTexture(
            cls.renderer.renderer,
            sdl2.SDL_PIXELFORMAT_ARGB1555,
            sdl2.SDL_TEXTUREACCESS_TARGET,
            Device.get_device().screen_width(),
            Device.get_device().screen_height()
        )
        sdl2.SDL_SetRenderTarget(cls.renderer.renderer, cls.render_canvas)
        sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, cls.bg_canvas, None, None)

    @classmethod
    def unlock_current_image(cls):
        PyUiLogger.get_logger().warning("Unlocking current iamge as background")
        if cls.bg_canvas:
            sdl2.SDL_DestroyTexture(cls.bg_canvas)
            cls.bg_canvas = None

    @classmethod
    def clear(cls, 
              top_bar_text, 
              hide_top_bar_icons = False,
              bottom_bar_text = None,
              render_bottom_bar_icons_and_images = True,
              force_top_and_bottom_bar = False):
        cls.top_bar_text = top_bar_text
        
        if cls.is_custom_theme_background:
            #cls.render_image(cls.bg_path, Device.get_device().screen_width()//2, Device.get_device().screen_height()//2, RenderMode.MIDDLE_CENTER_ALIGNED, Device.get_device().screen_width(), Device.get_device().screen_height(), ResizeType.ZOOM)
            cls.render_image(cls.bg_path, 0, 0, RenderMode.TOP_LEFT_ALIGNED, Device.get_device().screen_width(), Device.get_device().screen_height(), ResizeType.ZOOM)
        elif cls.bg_canvas is not None:
            sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, cls.bg_canvas, None, None)
        elif cls.background_texture is not None:
            sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, cls.background_texture, None, None)
        else:
            PyUiLogger.get_logger().warning("No background texture to render")
        

        if not Theme.render_top_and_bottom_bar_last() or force_top_and_bottom_bar:
            cls.top_bar.render_top_bar(cls.top_bar_text,hide_top_bar_icons)
            cls.bottom_bar.render_bottom_bar(bottom_bar_text, render_bottom_bar_icons_and_images=render_bottom_bar_icons_and_images)

    @classmethod
    def _log(cls, msg):
        if cls.debug:
            PyUiLogger.get_logger().info(msg)

    @staticmethod
    def _calculate_scaled_width_and_height(orig_w, orig_h, target_width, target_height, resize_type):
        if resize_type == ResizeType.FIT:
            if target_width and target_height:
                scale = min(target_width / orig_w, target_height / orig_h)
            elif target_width:
                scale = target_width / orig_w
            elif target_height:
                scale = target_height / orig_h
            else:
                scale = 1.0
            render_w = int(orig_w * scale)
            render_h = int(orig_h * scale)

        elif resize_type == ResizeType.ZOOM:
            if target_width and target_height:
                scale = max(target_width / orig_w, target_height / orig_h)
                render_w = int(orig_w * scale)
                render_h = int(orig_h * scale)
            else:
                render_w = orig_w
                render_h = orig_h
        else:
            render_w = orig_w
            render_h = orig_h

        return render_w, render_h


    @classmethod
    def _render_surface_texture(cls, x, y, texture, surface, render_mode: RenderMode, texture_id,
                                scale_width=None, scale_height=None, crop_w=None, crop_h=None,
                                resize_type=ResizeType.FIT):
        #If resize_type is none set it to fit for now,
        #Need to push this further up stream though
        if(resize_type is None):
            resize_type=ResizeType.FIT
        
        orig_w = surface.contents.w
        orig_h = surface.contents.h
        render_w, render_h = cls._calculate_scaled_width_and_height(orig_w, orig_h, scale_width, scale_height, resize_type)

        # Adjust position based on render mode
        adj_x = x
        adj_y = y
                
        if resize_type == ResizeType.ZOOM and scale_width and scale_height:
            src_w = int(scale_width * (orig_w / render_w))
            src_h = int(scale_height * (orig_h / render_h))

            if YRenderOption.CENTER == render_mode.y_mode:
                adj_y = y - (scale_height or render_h) // 2
                src_y = max(0, (orig_h - src_h) // 2)
            elif YRenderOption.BOTTOM == render_mode.y_mode:
                adj_y = y - (scale_height or render_h)
                src_y = max(0, (orig_h - src_h))
            elif(YRenderOption.TOP == render_mode.y_mode):
                src_y = 0
            else:
                src_y = max(0, (orig_h - src_h) // 2)

            if XRenderOption.CENTER == render_mode.x_mode:
                adj_x = x - (scale_width or render_w) // 2
                src_x = max(0, (orig_w - src_w) // 2)
            elif XRenderOption.RIGHT == render_mode.x_mode:
                adj_x = x - (scale_width or render_w)
                src_x = max(0, orig_w - src_w)
            elif(XRenderOption.LEFT == render_mode.x_mode):
                src_x = 0
            else:
                src_x = max(0, (orig_w - src_w) // 2)

            adj_x = int(adj_x)
            adj_y = int(adj_y)

            src_rect = sdl2.SDL_Rect(src_x, src_y, src_w, src_h)
            dst_rect = sdl2.SDL_Rect(adj_x, adj_y, scale_width, scale_height)

            sdl2.SDL_RenderCopy(cls.renderer.renderer, texture, src_rect, dst_rect)

            return scale_width, scale_height
        else:
                
            if XRenderOption.CENTER == render_mode.x_mode:
                adj_x = x - (render_w) // 2
            elif XRenderOption.RIGHT == render_mode.x_mode:
                adj_x = x - (render_w)

            if YRenderOption.CENTER == render_mode.y_mode:
                adj_y = y - (render_h) // 2
            elif YRenderOption.BOTTOM == render_mode.y_mode:
                adj_y = y - (render_h)

            adj_x = int(adj_x)
            adj_y = int(adj_y)

            # Handle regular FIT or uncropped draw
            if crop_w is None and crop_h is None:
                rect = sdl2.SDL_Rect(adj_x, adj_y, render_w, render_h)
                sdl2.SDL_RenderCopy(cls.renderer.renderer, texture, None, rect)
            else:
                if crop_w is None or crop_w > orig_w:
                    crop_w = orig_w
                if crop_h is None or crop_h > orig_h:
                    crop_h = orig_h

                src_rect = sdl2.SDL_Rect(0, 0, crop_w, crop_h)
                dst_rect = sdl2.SDL_Rect(adj_x, adj_y, crop_w, crop_h)
                sdl2.SDL_RenderCopy(cls.renderer.renderer, texture, src_rect, dst_rect)

            return render_w, render_h

    @classmethod
    def log_sdl_error_and_clear_cache_image(cls, image_path=None):
        err = sdl2.sdlttf.TTF_GetError()
        err_msg = err.decode('utf-8') if err else "Unknown error"
        PyUiLogger.get_logger().warning(f"SDL Error received on loading {image_path} : {err_msg}")
        
        if any(keyword in err_msg for keyword in cls._problematic_image_keywords):
            if(image_path is not None):
                cls._problematic_images.add(image_path)
                PyUiLogger.get_logger().warning(f"Marking as image to permanently stop trying to load: {image_path}")
            
            return False
        else:
            PyUiLogger.get_logger().warning(f"Clearing cache : {err_msg}")
            cls._text_texture_cache.clear_cache()
            cls._image_texture_cache.clear_cache()
            return True


    @classmethod
    def log_sdl_error_and_clear_cache_text(cls, text,purpose):
        err = sdl2.sdlttf.TTF_GetError()
        err_msg = err.decode('utf-8') if err else "Unknown error"
        
        if not (any(keyword in err_msg for keyword in cls._problematic_image_keywords)):
            PyUiLogger.get_logger().warning(f"SDL Error received on loading {text} w/ purpose {purpose}")
            PyUiLogger.get_logger().warning(f"Clearing cache : {err_msg}")
            cls._text_texture_cache.clear_cache()
            cls._image_texture_cache.clear_cache()
            return True
        
        return False


    @classmethod
    def render_text(cls, text, x, y, color, purpose: FontPurpose, render_mode=RenderMode.TOP_LEFT_ALIGNED,
                    crop_w=None, crop_h=None, alpha=None):
        text = Display.split_message(text, purpose, clip_to_device_width=False)[0]
        if(text is None or len(text) == 0):
            return 0, 0
        loaded_font = cls.fonts[purpose]
        cache : CachedImageTexture = cls._text_texture_cache.get_texture(text, purpose, color)
        cached = True
        if cache and alpha is None:
            surface = cache.surface
            texture = cache.texture
        else:
            sdl_color = sdl2.SDL_Color(color[0], color[1], color[2])
            surface = sdl2.sdlttf.TTF_RenderUTF8_Blended(loaded_font.font, text.encode('utf-8'), sdl_color)
            if not surface:
                if not cls.log_sdl_error_and_clear_cache_text(text,purpose):
                    return 0, 0
                surface = sdl2.sdlttf.TTF_RenderUTF8_Blended(loaded_font.font, text.encode('utf-8'), sdl_color)
                if not surface:
                    PyUiLogger.get_logger().error(f"Failed to render text surface for {text}: {sdl2.sdlttf.TTF_GetError().decode('utf-8')}")
                    return 0, 0

            texture = sdl2.SDL_CreateTextureFromSurface(cls.renderer.renderer, surface)
            if not texture:
                if not cls.log_sdl_error_and_clear_cache_text(text,purpose):
                    sdl2.SDL_FreeSurface(surface)
                    return 0, 0
                texture = sdl2.SDL_CreateTextureFromSurface(cls.renderer.renderer, surface)
                if not texture:
                    err = sdl2.sdlttf.TTF_GetError()
                    err_msg = err.decode('utf-8') if err else "Unknown error"
                    PyUiLogger.get_logger().error(f"Failed to create texture from surface {text}: {sdl2.sdlttf.TTF_GetError().decode('utf-8')} : {err_msg}")
                    PyUiLogger.get_logger().error(f"Surface w,h: {surface.contents.w},{surface.contents.h}")
                    sdl2.SDL_FreeSurface(surface)
                    return 0, 0

            if(alpha is not None):
                sdl2.SDL_SetTextureBlendMode(texture, sdl2.SDL_BLENDMODE_BLEND)
                sdl2.SDL_SetTextureAlphaMod(texture, alpha)
                w,h = cls._render_surface_texture(
                        x=x,
                        y=y, 
                        texture=texture, 
                        surface=surface, 
                        render_mode=render_mode, 
                        texture_id=text, 
                        crop_w=crop_w, 
                        crop_h=crop_h)
                sdl2.SDL_DestroyTexture(texture)
                sdl2.SDL_FreeSurface(surface)
                return w,h
            else:
                cached = cls._text_texture_cache.add_texture(text, purpose, color, surface, texture)

        w,h = cls._render_surface_texture(
                x=x,
                y=y, 
                texture=texture, 
                surface=surface, 
                render_mode=render_mode, 
                texture_id=text, 
                crop_w=crop_w, 
                crop_h=crop_h)
        
        if not cached:
            sdl2.SDL_DestroyTexture(texture)
            sdl2.SDL_FreeSurface(surface)

        return w,h

    @classmethod
    def render_text_centered(cls, text, x, y, color, purpose: FontPurpose):
        return cls.render_text(text, x, y, color, purpose, RenderMode.TOP_CENTER_ALIGNED)

    @classmethod
    def image_load(cls, image_path):
        #PyUiLogger.get_logger().info(f"Loading {image_path}")
        return sdl2.sdlimage.IMG_Load(image_path.encode("utf-8"))
    
    @classmethod
    def convert_surface_to_safe_format(cls, surface):
        if(Device.get_device().might_require_surface_format_conversion() and surface):
            surface_format = surface.contents.format.contents.format
            if surface_format not in cls.supported_formats:
                # Convert to safe format
                converted_surface = sdl2.SDL_ConvertSurfaceFormat(
                    surface, sdl2.SDL_PIXELFORMAT_ARGB1555, 0
                )
                sdl2.SDL_FreeSurface(surface)
                surface = converted_surface

        return surface
                     
    @classmethod
    def render_image(cls, image_path: str, x: int, y: int, render_mode=RenderMode.TOP_LEFT_ALIGNED, target_width=None, target_height=None, resize_type=None, crop_w=None, crop_h=None):        
        if(image_path is None or image_path in cls._problematic_images):
            return 0, 0

        cache : CachedImageTexture = cls._image_texture_cache.get_texture(image_path)
        cached = True
        if cache:
            surface = cache.surface
            texture = cache.texture
        else:
            surface = Display.image_load(image_path)
            surface = cls.convert_surface_to_safe_format(surface)
            if not surface:
                if not cls.log_sdl_error_and_clear_cache_image(image_path):
                    return 0,0
                surface = Display.image_load(image_path)
                surface = cls.convert_surface_to_safe_format(surface)
                if not surface:
                    PyUiLogger.get_logger().error(f"Failed to load image: {image_path}")
                    return 0, 0



            texture = sdl2.SDL_CreateTextureFromSurface(cls.renderer.renderer, surface)

            surface_width = surface.contents.w
            surface_height = surface.contents.h

            if(surface_width > Device.get_device().max_texture_width() or surface_height > Device.get_device().max_texture_height()):
                sdl2.SDL_FreeSurface(surface)
                PyUiLogger.get_logger().warning(
                    f"Image is too large to render ({surface_width} x {surface_height} with max of {Device.get_device().max_texture_width()} x {Device.get_device().max_texture_height()}). Skipping {image_path}\n"
                ) 
                cls._problematic_images.add(image_path)
                return 0, 0


            if not texture:
                if not cls.log_sdl_error_and_clear_cache_image(image_path):
                    sdl2.SDL_FreeSurface(surface)
                    return 0,0

                texture = sdl2.SDL_CreateTextureFromSurface(cls.renderer.renderer, surface)
                if not texture:
                    sdl2.SDL_FreeSurface(surface)
                    PyUiLogger.get_logger().info(f"{image_path} : {surface_width} x {surface_height}")
                    PyUiLogger.get_logger().error("Failed to create texture from surface")
                    cls._text_texture_cache.clear_cache()
                    cls._image_texture_cache.clear_cache()
                    return 0, 0

            sdl2.SDL_SetTextureBlendMode(texture, sdl2.SDL_BLENDMODE_BLEND)
            cached = cls._image_texture_cache.add_texture(image_path,surface, texture)

        w,h = cls._render_surface_texture(x=x, 
                                           y=y, 
                                           texture=texture, 
                                           surface=surface, 
                                           render_mode=render_mode, 
                                           scale_width=target_width, 
                                           scale_height=target_height,
                                           resize_type=resize_type, 
                                           texture_id=image_path,
                                           crop_w=crop_w, crop_h=crop_h)
        
        if(not cached):
            sdl2.SDL_DestroyTexture(texture)
            sdl2.SDL_FreeSurface(surface)
            PyUiLogger.get_logger().info(f"Destroyed {image_path}. Image cache size is {cls._image_texture_cache.size()}");
        
        return w,h

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
            sdl2.SDL_PIXELFORMAT_ARGB1555,
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

    FADE_DURATION_MS = 96  # 0.25 seconds

    @classmethod
    def fade_transition(cls, texture1, texture2):
        renderer = cls.renderer.renderer

        # Get renderer output size (window size)
        width = ctypes.c_int()
        height = ctypes.c_int()
        sdl2.SDL_GetRendererOutputSize(renderer, width, height)

        # Create an intermediate render target texture
        render_target = sdl2.SDL_CreateTexture(
            renderer,
            sdl2.SDL_PIXELFORMAT_ARGB1555,
            sdl2.SDL_TEXTUREACCESS_TARGET,
            width.value, height.value
        )

        # Enable blending on both target and texture2
        sdl2.SDL_SetTextureBlendMode(texture2, sdl2.SDL_BLENDMODE_BLEND)
        sdl2.SDL_SetTextureBlendMode(render_target, sdl2.SDL_BLENDMODE_BLEND)

        TARGET_FRAME_MS = 16
        start_time = sdl2.SDL_GetTicks()

        while True:
            frame_start = sdl2.SDL_GetTicks()

            now = sdl2.SDL_GetTicks()
            elapsed = now - start_time
            alpha = int(255 * (elapsed / cls.FADE_DURATION_MS))
            if alpha > 255:
                alpha = 255

            sdl2.SDL_SetTextureAlphaMod(texture2, alpha)

            # Set render target to the intermediate texture
            sdl2.SDL_SetRenderTarget(renderer, render_target)

            # Composite both images into the target
            sdl2.SDL_RenderClear(renderer)
            sdl2.SDL_RenderCopy(renderer, texture1, None, None)
            sdl2.SDL_RenderCopy(renderer, texture2, None, None)

            # Set render target back to default (the screen)
            sdl2.SDL_SetRenderTarget(renderer, None)

            # Draw final composited texture to the screen
            sdl2.SDL_RenderClear(renderer)
            sdl2.SDL_RenderCopy(renderer, render_target, None, None)
            sdl2.SDL_RenderPresent(renderer)

            if alpha == 255:
                break

            # Frame pacing
            frame_time = sdl2.SDL_GetTicks() - frame_start
            delay = TARGET_FRAME_MS - frame_time
            if delay > 0:
                sdl2.SDL_Delay(delay)

        # Cleanup render target (optional, good practice)
        sdl2.SDL_DestroyTexture(render_target)


    @classmethod
    def rotate_canvas(cls) -> sdl2.SDL_Texture:
        """
        Rotates a texture by a given angle (supports 90, 180, 270) without scaling.
        Returns a new texture with dimensions swapped if needed.
        """
        # Query source texture size
        w = sdl2.c_int()
        h = sdl2.c_int()
        query_texture_result = sdl2.SDL_QueryTexture(cls.render_canvas, None, None, w, h)
        
        if query_texture_result != 0:
            # Destroy the old texture if it exists
            if cls.render_canvas:
                sdl2.SDL_DestroyTexture(cls.render_canvas)
                cls.render_canvas = None

            # Decide default size (fallback to current display size)
            width, height = Device.get_device().screen_width(), Device.get_device().screen_height()

            cls.render_canvas = sdl2.SDL_CreateTexture(
                cls.renderer.sdlrenderer,
                sdl2.SDL_PIXELFORMAT_ARGB1555,
                sdl2.SDL_TEXTUREACCESS_TARGET,
                width,
                height
            )
            if not cls.render_canvas:
                PyUiLogger.get_logger().error("Failed to recreate render_canvas: " + sdl2.SDL_GetError().decode())
                return None        
            
        src_w, src_h = w.value, h.value

        # Determine new target size after rotation
        angle_mod = Device.get_device().screen_rotation() % 360
        if angle_mod in (90, 270):
            new_w, new_h = src_h, src_w
        else:
            new_w, new_h = src_w, src_h

        # Create a new target texture
        rotated_texture = sdl2.SDL_CreateTexture(
            cls.renderer.sdlrenderer,
            sdl2.SDL_PIXELFORMAT_ARGB1555,
            sdl2.SDL_TEXTUREACCESS_TARGET,
            new_w,
            new_h
        )
        if not rotated_texture:
            PyUiLogger.get_logger().error(f"new_w = {new_w}, new_h = {new_h}")
            PyUiLogger.get_logger().error("Failed to create target texture: " + sdl2.SDL_GetError().decode())
            return None

        # Set render target
        sdl2.SDL_SetRenderTarget(cls.renderer.sdlrenderer, rotated_texture)
        
        # Clear it
        sdl2.SDL_SetRenderDrawColor(cls.renderer.sdlrenderer, 0, 0, 0, 0)
        sdl2.SDL_RenderClear(cls.renderer.sdlrenderer)

        # Destination rectangle uses **original texture size** (no scaling)
        dst_rect = sdl2.SDL_Rect(
            (new_w - src_w) // 2,  # center horizontally
            (new_h - src_h) // 2,  # center vertically
            src_w,
            src_h
        )

        # Center of rotation inside the dst_rect
        center = sdl2.SDL_Point(src_w // 2, src_h // 2)

        # Render with rotation
        sdl2.SDL_RenderCopyEx(
            cls.renderer.sdlrenderer,
            cls.render_canvas,
            None,
            dst_rect,
            Device.get_device().screen_rotation(),
            center,
            sdl2.SDL_FLIP_NONE
        )

        # Reset render target
        sdl2.SDL_SetRenderTarget(cls.renderer.sdlrenderer, None)

        return rotated_texture
         
    @classmethod
    def present(cls, fade=False):
        if Theme.render_top_and_bottom_bar_last():
            cls.top_bar.render_top_bar(cls.top_bar_text)
            cls.bottom_bar.render_bottom_bar()

        sdl2.SDL_SetRenderTarget(cls.renderer.renderer, None)

        if Device.get_device().should_scale_screen():
            scaled_canvas = cls.scale_texture_to_fit(cls.render_canvas, Device.get_device().output_screen_width(), Device.get_device().output_screen_height())
            sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, scaled_canvas, None, None)
            sdl2.SDL_DestroyTexture(scaled_canvas)
        elif(0 == Device.get_device().screen_rotation()):
            if(fade):
                cls.fade_transition(cls.bg_canvas, cls.render_canvas)
            else:
                sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, cls.render_canvas, None, None)
        else:   
                rotated_texture = cls.rotate_canvas()
                if(rotated_texture is not None):
                    sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, rotated_texture, None, None)
                    sdl2.SDL_DestroyTexture(rotated_texture)  # free GPU memory

        sdl2.SDL_SetRenderTarget(cls.renderer.renderer, cls.render_canvas)
        cls.renderer.present()

    #TODO make default false and fix everywhere
    @classmethod
    def get_top_bar_height(cls, force_include_top_bar = True):
        return 0 if Theme.ignore_top_and_bottom_bar_for_layout() and not force_include_top_bar else cls.top_bar.get_top_bar_height()

    @classmethod
    def get_bottom_bar_height(cls):
        return 0 if Theme.ignore_top_and_bottom_bar_for_layout() else cls.bottom_bar.get_bottom_bar_height()

    @classmethod
    def get_usable_screen_height(cls, force_include_top_bar = False):
        return Device.get_device().screen_height() if Theme.ignore_top_and_bottom_bar_for_layout() and not force_include_top_bar else Device.get_device().screen_height() - cls.get_bottom_bar_height() - cls.get_top_bar_height()

    @classmethod
    def get_center_of_usable_screen_height(cls, force_include_top_bar = False):
        return ((Device.get_device().screen_height() - cls.get_bottom_bar_height() - cls.get_top_bar_height(force_include_top_bar)) // 2) + cls.get_top_bar_height(force_include_top_bar)

    @classmethod
    def get_image_dimensions(cls, img):
        if(img is None):
            return 0, 0
        
        surface = Display.image_load(img)
        if not surface:
            return 0, 0
        width, height = surface.contents.w, surface.contents.h
        sdl2.SDL_FreeSurface(surface)
        return width, height


    _cached_space_dimensions = None  # class-level cache
    @classmethod
    def get_space_dimensions(cls, font_purpose=FontPurpose.LIST):
        """
        Returns the width and height of a space character for the given font.
        Caches the result after the first calculation.
        """
        if cls._cached_space_dimensions is None:
            cls._cached_space_dimensions = cls.get_text_dimensions(font_purpose, " ")
        return cls._cached_space_dimensions
    
    @classmethod
    def get_text_dimensions(cls, purpose, text="A"):
        w = sdl2.Sint32()
        h = sdl2.Sint32()
        sdl2.sdlttf.TTF_SizeUTF8(cls.fonts[purpose].font, text.encode('utf-8'), w, h)
        return int(w.value * Device.get_device().get_text_width_measurement_multiplier()), h.value
    
    @classmethod
    def add_index_text(cls, index, total, force_include_index = False, letter = None):
        if(force_include_index or Theme.show_index_text()):
            y_padding = max(5, cls.get_bottom_bar_height() // 4)
            y_value = Device.get_device().screen_height() - y_padding
            x_padding = 10

            x_offset = Device.get_device().screen_width() - x_padding
            total_text_w, _ = cls.render_text(
                str(total),
                x_offset,
                y_value,
                Theme.text_color(FontPurpose.LIST_TOTAL),
                FontPurpose.LIST_TOTAL,
                RenderMode.BOTTOM_RIGHT_ALIGNED
            )

            x_offset -= total_text_w
            index_text_w, index_text_h = cls.render_text(
                str(index).zfill(len(str(total))) + "/",
                x_offset,
                y_value,
                Theme.text_color(FontPurpose.LIST_INDEX),
                FontPurpose.LIST_INDEX,
                RenderMode.BOTTOM_RIGHT_ALIGNED
            )

            x_offset -= index_text_w  + x_padding
            if(letter is not None):
                cls.render_text(
                    letter,
                    x_offset,
                    y_value,
                    Theme.text_color(FontPurpose.LIST_INDEX),
                    FontPurpose.LIST_INDEX,
                    RenderMode.BOTTOM_RIGHT_ALIGNED
                )


    @classmethod
    def get_current_top_bar_title(cls):
        return cls.top_bar.get_current_title()

    @classmethod
    def volume_changed(cls, vol):
        cls.top_bar.volume_changed(vol)

    @classmethod
    def is_text_too_long(cls, line: str, font_purpose, clip_to_device_width) -> bool:
        try:
            if(Device.get_device().get_guaranteed_safe_max_text_char_count() >= len(line)):
                return False
            text_w, text_h = Display.get_text_dimensions(font_purpose, line)
            max_width = Device.get_device().max_texture_width()
            if(clip_to_device_width):
                max_width = min(max_width, Device.get_device().screen_width())
            max_width = max_width - int(10 * Device.get_device().screen_height()/480)
            return text_w > max_width
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Error checking text length: {e}")
            return False

    @classmethod
    def split_message(cls, message: str, font_purpose, clip_to_device_width) -> list[str]:
        if not message:
            return [""]

        # Convert anything that's not a string to string
        if not isinstance(message, str):
            message = str(message)
            
        # First split on explicit newlines
        raw_lines = message.split("\n")
        final_lines = []

        for raw_line in raw_lines:
            # If the line is empty (because of "\n\n"), preserve it
            if raw_line.strip() == "":
                final_lines.append("")
                continue

            # If line fits as-is, keep it
            if not cls.is_text_too_long(raw_line, font_purpose, clip_to_device_width):
                final_lines.append(raw_line)
                continue

            # Otherwise word-wrap this raw_line
            words = raw_line.split()
            current_line = ""

            for word in words:
                tentative_line = (current_line + " " + word).strip()

                # If adding this word makes the line too long, start a new one
                if current_line and cls.is_text_too_long(tentative_line, font_purpose, clip_to_device_width):
                    final_lines.append(current_line)
                    current_line = word
                else:
                    current_line = tentative_line

            if current_line:
                final_lines.append(current_line)

        return final_lines



    @classmethod
    def display_message_multiline(cls,split_message, duration_ms=0):
        Display.clear("")        
        cls.write_message_multiline(split_message, Device.get_device().screen_height()//2)
        Display.present()
        # Sleep for the specified duration in milliseconds
        time.sleep(duration_ms / 1000)

    @classmethod
    def write_message_multiline(cls,split_message, middle_height):
        text_w,text_h = Display.get_text_dimensions(FontPurpose.LIST, "W")

        height_per_line = text_h + int(5 * Device.get_device().screen_height()/480)
        starting_height = middle_height - (len(split_message) * height_per_line)//2

        for i, line in enumerate(split_message):
            Display.render_text_centered(f"{line}",Device.get_device().screen_width()//2, starting_height + i * height_per_line,
                                         Theme.text_color(FontPurpose.LIST), purpose=FontPurpose.LIST)


    @classmethod
    def write_message_multiline_starting_height_specified(cls,split_message, starting_height):
        text_w,text_h = Display.get_text_dimensions(FontPurpose.LIST, "W")

        height_per_line = text_h + int(5 * Device.get_device().screen_height()/480)

        for i, line in enumerate(split_message):
            Display.render_text_centered(f"{line}",Device.get_device().screen_width()//2, starting_height + i * height_per_line,
                                         Theme.text_color(FontPurpose.LIST), purpose=FontPurpose.LIST)


    @classmethod
    def display_message(cls,message, duration_ms=0):
        split_message = Display.split_message(message, FontPurpose.LIST,clip_to_device_width=True)
        cls.display_message_multiline(split_message,duration_ms)
        
    @classmethod
    def display_image(cls,image_path, duration_ms=0):
        Display.clear("")
        Display.render_image(image_path,Device.get_device().screen_width()//2,Device.get_device().screen_height()//2,RenderMode.MIDDLE_CENTER_ALIGNED)
        Display.present()
        # Sleep for the specified duration in milliseconds
        time.sleep(duration_ms / 1000)