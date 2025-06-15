from dataclasses import dataclass
from enum import Enum, auto
import os
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
from ctypes import c_double

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
    
    def clear_cache(self):
        for entry in self.cache.values():
            sdl2.SDL_DestroyTexture(entry.texture)
            sdl2.SDL_FreeSurface(entry.surface)
        self.cache.clear()

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
    page = ""
    top_bar = TopBar()
    bottom_bar = BottomBar()
    window = None
    background_texture = None
    top_bar_text = None
    _image_texture_cache = ImageTextureCache()
    _text_texture_cache = TextTextureCache()

    @classmethod
    def init(cls):
        cls._init_display()
        #Outside init_fonts as it should only ever be called once
        if sdl2.sdlttf.TTF_Init() == -1:
            raise RuntimeError("Failed to initialize SDL_ttf")
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
        sdl2.SDL_SetRenderDrawBlendMode(cls.renderer.renderer, sdl2.SDL_BLENDMODE_BLEND)
        PyUiLogger.get_logger().info(f"sdl2.SDL_GetError() : {sdl2.SDL_GetError()}")
        cls.restore_bg()
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
        PyUiLogger.get_logger().debug("Clearing text cache")    
        cls._text_texture_cache.clear_cache()
        cls.deinit_fonts()
        cls.init_fonts()

    @classmethod
    def clear_image_cache(cls):
        PyUiLogger.get_logger().debug("Clearing image cache")    
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
    def reinitialize(cls):
        cls.deinit_display()
        cls._unload_bg_texture()
        cls._init_display()
        cls.init_fonts()
        cls.restore_bg()
        cls.clear("reinitialize")
        cls.present()


    @classmethod
    def _unload_bg_texture(cls):
        if cls.background_texture:
            sdl2.SDL_DestroyTexture(cls.background_texture)
            cls.background_texture = None
            PyUiLogger.get_logger().debug("Destroying bg texture")

    @classmethod
    def restore_bg(cls):
        cls.set_new_bg(Theme.background())

    @classmethod
    def set_new_bg(cls, bg_path):
        cls._unload_bg_texture()
        cls.bg_path = bg_path
        PyUiLogger.get_logger().info(f"Using {bg_path} as the background")
        if(bg_path is not None):
            surface = sdl2.sdlimage.IMG_Load(cls.bg_path.encode('utf-8'))
            if not surface:
                PyUiLogger.get_logger().error(f"Failed to load image: {cls.bg_path}")
                return

            cls.background_texture = sdl2.SDL_CreateTextureFromSurface(cls.renderer.renderer, surface)
            sdl2.SDL_FreeSurface(surface)

            if not cls.background_texture:
                PyUiLogger.get_logger().error("Failed to create texture from surface")

    @classmethod
    def set_page(cls, page):
        if(page != cls.page):
            cls.page = page 
            background = Theme.background(page)
            if(os.path.exists(background)):
                cls.set_new_bg(background)
            else:
                PyUiLogger.get_logger().debug(f"Theme did not provide bg for {background}")

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
        if cls.bg_canvas:
            sdl2.SDL_DestroyTexture(cls.bg_canvas)
            cls.bg_canvas = None
    
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
    def unlock_current_image(cls):
        if cls.bg_canvas:
            sdl2.SDL_DestroyTexture(cls.bg_canvas)
            cls.bg_canvas = None

    @classmethod
    def clear(cls, 
              top_bar_text, 
              hide_top_bar_icons = False,
              bottom_bar_text = None,
              render_bottom_bar_icons_and_images = True):
        cls.top_bar_text = top_bar_text

        if cls.bg_canvas is not None:
            sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, cls.bg_canvas, None, None)
        elif cls.background_texture is not None:
            sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, cls.background_texture, None, None)

        if not Theme.render_top_and_bottom_bar_last():
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

            if XRenderOption.CENTER == render_mode.x_mode:
                adj_x = x - (scale_width or render_w) // 2
            elif XRenderOption.RIGHT == render_mode.x_mode:
                adj_x = x - (scale_width or render_w)

            if YRenderOption.CENTER == render_mode.y_mode:
                adj_y = y - (scale_height or render_h) // 2
            elif YRenderOption.BOTTOM == render_mode.y_mode:
                adj_y = y - (scale_height or render_h)

            adj_x = int(adj_x)
            adj_y = int(adj_y)
            # Calculate cropping to center the zoomed image
            src_w = int(scale_width * (orig_w / render_w))
            src_h = int(scale_height * (orig_h / render_h))
            src_x = max(0, (orig_w - src_w) // 2)
            src_y = max(0, (orig_h - src_h) // 2)

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
    def render_text(cls, text, x, y, color, purpose: FontPurpose, render_mode=RenderMode.TOP_LEFT_ALIGNED,
                    crop_w=None, crop_h=None, alpha=None):
        loaded_font = cls.fonts[purpose]
        cache : CachedImageTexture = cls._text_texture_cache.get_texture(text, purpose, color)
        
        if cache and alpha is None:
            surface = cache.surface
            texture = cache.texture
        else:
            sdl_color = sdl2.SDL_Color(color[0], color[1], color[2])
            surface = sdl2.sdlttf.TTF_RenderUTF8_Blended(loaded_font.font, text.encode('utf-8'), sdl_color)
            if not surface:
                PyUiLogger.get_logger().error(f"Failed to render text surface for {text}: {sdl2.sdlttf.TTF_GetError().decode('utf-8')}")
                return 0, 0

            texture = sdl2.SDL_CreateTextureFromSurface(cls.renderer.renderer, surface)
            if not texture:
                sdl2.SDL_FreeSurface(surface)
                PyUiLogger.get_logger().error(f"Failed to create texture from surface {text}: {sdl2.sdlttf.TTF_GetError().decode('utf-8')}")
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
                cls._text_texture_cache.add_texture(text, purpose, color, surface, texture)

        return cls._render_surface_texture(
                x=x,
                y=y, 
                texture=texture, 
                surface=surface, 
                render_mode=render_mode, 
                texture_id=text, 
                crop_w=crop_w, 
                crop_h=crop_h)

    @classmethod
    def render_text_centered(cls, text, x, y, color, purpose: FontPurpose):
        return cls.render_text(text, x, y, color, purpose, RenderMode.TOP_CENTER_ALIGNED)

    @classmethod
    def render_image(cls, image_path: str, x: int, y: int, render_mode=RenderMode.TOP_LEFT_ALIGNED, target_width=None, target_height=None, resize_type=None):
        if(image_path is None):
            return 0, 0

        cache : CachedImageTexture = cls._image_texture_cache.get_texture(image_path)
        
        if cache:
            surface = cache.surface
            texture = cache.texture
        else:
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
            cls._image_texture_cache.add_texture(image_path,surface, texture)

        return cls._render_surface_texture(x=x, 
                                           y=y, 
                                           texture=texture, 
                                           surface=surface, 
                                           render_mode=render_mode, 
                                           scale_width=target_width, 
                                           scale_height=target_height,
                                           resize_type=resize_type, 
                                           texture_id=image_path)

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
            sdl2.SDL_PIXELFORMAT_RGBA8888,
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
    def present(cls, fade=False):
        if Theme.render_top_and_bottom_bar_last():
            cls.top_bar.render_top_bar(cls.top_bar_text)
            cls.bottom_bar.render_bottom_bar()

        sdl2.SDL_SetRenderTarget(cls.renderer.renderer, None)

        if Device.should_scale_screen():
            scaled_canvas = cls.scale_texture_to_fit(cls.render_canvas, Device.output_screen_width, Device.output_screen_height)
            sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, scaled_canvas, None, None)
            sdl2.SDL_DestroyTexture(scaled_canvas)
        elif(0 == Device.screen_rotation()):
            if(fade):
                cls.fade_transition(cls.bg_canvas, cls.render_canvas)
            else:
                sdl2.SDL_RenderCopy(cls.renderer.sdlrenderer, cls.render_canvas, None, None)
        else:
            sdl2.SDL_RenderCopyEx(
                cls.renderer.sdlrenderer,     # Renderer
                cls.render_canvas,            # Texture (canvas)
                None,                         # Source rect (None = full texture)
                None,                         # Destination rect (None = full screen)
                c_double(Device.screen_rotation()),                        # Angle in degrees
                None,                         # Center point (None = center of dest rect)
                sdl2.SDL_FLIP_NONE            # Flip (you can also use SDL_FLIP_HORIZONTAL or _VERTICAL if needed)
            )
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
        return Device.screen_height() if Theme.ignore_top_and_bottom_bar_for_layout() and not force_include_top_bar else Device.screen_height() - cls.get_bottom_bar_height() - cls.get_top_bar_height()

    @classmethod
    def get_center_of_usable_screen_height(cls, force_include_top_bar = False):
        return ((Device.screen_height() - cls.get_bottom_bar_height() - cls.get_top_bar_height(force_include_top_bar)) // 2) + cls.get_top_bar_height(force_include_top_bar)

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
    def add_index_text(cls, index, total, force_include_index = False, letter = None):
        if(force_include_index or Theme.show_index_text()):
            y_padding = max(5, cls.get_bottom_bar_height() // 4)
            y_value = Device.screen_height() - y_padding
            x_padding = 10

            x_offset = Device.screen_width() - x_padding
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

