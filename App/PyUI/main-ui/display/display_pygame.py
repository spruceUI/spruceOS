"""
SDL1.2/Pygame implementation of Display
Provides the same public API as display.py but uses pygame (SDL1.2) internally
For use with legacy hardware like Miyoo Mini that only supports SDL1.2
"""

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
from themes.theme import Theme
from utils.logger import PyUiLogger
import traceback

from utils.time_logger import log_timing

# Import pygame for SDL1.2 support
import pygame
import pygame.font
import pygame.image
import pygame.transform


@dataclass
class CachedImageSurface:
    def __init__(self, surface):
        self.surface = surface


class ImageSurfaceCache:
    def __init__(self):
        self.cache = {}

    def get_surface(self, surface_id) -> CachedImageSurface:
        return self.cache.get(surface_id)

    def add_surface(self, surface_id, surface):
        self.cache[surface_id] = CachedImageSurface(surface)
        return True

    def clear_cache(self):
        # Pygame surfaces are automatically freed when dereferenced
        self.cache.clear()

    def size(self):
        return len(self.cache)


@dataclass(frozen=True)
class TextSurfaceKey:
    texture_id: str
    font: object
    color: tuple


@dataclass
class CachedTextSurface:
    def __init__(self, surface):
        self.surface = surface


class TextSurfaceCache:
    def __init__(self):
        self.cache = {}

    def get_surface(self, surface_id, font, color) -> CachedTextSurface:
        return self.cache.get(TextSurfaceKey(surface_id, font, color))

    def add_surface(self, surface_id, font, color, surface):
        self.cache[TextSurfaceKey(surface_id, font, color)] = CachedTextSurface(surface)
        return True

    def clear_cache(self):
        self.cache.clear()


class Display:
    debug = False
    screen = None  # Main display surface
    fonts = {}
    bg_canvas = None  # Background surface for locking
    render_canvas = None  # Off-screen rendering surface
    bg_path = ""
    top_bar = TopBar()
    bottom_bar = BottomBar()
    background_surface = None  # Loaded background image
    top_bar_text = None
    _image_surface_cache = ImageSurfaceCache()
    _text_surface_cache = TextSurfaceCache()
    _problematic_images = set()
    _problematic_image_keywords = [
        "No such file or directory",
        "Text has zero width",
        "Texture dimensions are limited",
        "Corrupt PNG"
    ]
    is_custom_theme_background = False
    _screen_width = 640
    _screen_height = 480

    @classmethod
    def init(cls):
        cls._init_display()

        with log_timing("pygame.font.init()", PyUiLogger.get_logger()):
            pygame.font.init()
            cls.init_fonts()

        # Create off-screen rendering surface (replaces render_canvas texture)
        with log_timing("pygame create render canvas", PyUiLogger.get_logger()):
            cls.render_canvas = pygame.Surface((cls._screen_width, cls._screen_height))

        # Check if device needs double init (ported from original)
        if Device.get_device().double_init_sdl_display():
            Display.deinit_display()
            Display.reinitialize()

        with log_timing("restore_bg", PyUiLogger.get_logger()):
            cls.restore_bg()

        with log_timing("clear", PyUiLogger.get_logger()):
            cls.clear("", force_top_and_bottom_bar=True)

    @classmethod
    def _init_display(cls):
        with log_timing("pygame.init", PyUiLogger.get_logger()):
            pygame.init()

        # Get screen dimensions from device
        cls._screen_width = Device.get_device().screen_width()
        cls._screen_height = Device.get_device().screen_height()

        with log_timing("pygame.display.set_mode", PyUiLogger.get_logger()):
            # SDL1.2 fullscreen mode
            cls.screen = pygame.display.set_mode(
                (cls._screen_width, cls._screen_height),
                pygame.FULLSCREEN | pygame.HWSURFACE | pygame.DOUBLEBUF
            )
            pygame.display.set_caption("Minimal SDL GUI")

    @classmethod
    def deinit_display(cls):
        if cls.render_canvas:
            cls.render_canvas = None
        if cls.bg_canvas:
            cls.bg_canvas = None
        if cls.screen:
            pygame.display.quit()
            cls.screen = None
        cls.deinit_fonts()
        cls._unload_bg_surface()
        cls._text_surface_cache.clear_cache()
        cls._image_surface_cache.clear_cache()

    @classmethod
    def clear_text_cache(cls):
        cls._text_surface_cache.clear_cache()
        cls.deinit_fonts()
        cls.init_fonts()

    @classmethod
    def clear_image_cache(cls):
        cls._image_surface_cache.clear_cache()

    @classmethod
    def clear_cache(cls):
        cls.clear_image_cache()
        cls.clear_text_cache()

    @classmethod
    def log_sdl_render_drivers(cls):
        """Stub for SDL2 compatibility - not applicable to pygame"""
        PyUiLogger.get_logger().info("Pygame backend - renderer info not available")

    @classmethod
    def log_current_renderer(cls):
        """Stub for SDL2 compatibility - not applicable to pygame"""
        PyUiLogger.get_logger().info("Pygame backend - using software rendering")

    @classmethod
    def log_sdl_error_if_any(cls):
        """Stub for SDL2 compatibility - pygame uses different error handling"""
        err = pygame.get_error()
        if err:
            PyUiLogger.get_logger().info(f"pygame.get_error(): {err}")

    @classmethod
    def convert_surface_to_safe_format(cls, surface):
        """
        Stub for SDL2 compatibility - pygame surfaces don't need format conversion
        Returns the surface unchanged
        """
        return surface

    @classmethod
    def deinit_fonts(cls):
        # Pygame fonts are automatically freed
        cls.fonts.clear()

    @classmethod
    def reinitialize(cls, bg=None):
        cls.deinit_display()
        cls._unload_bg_surface()
        cls._init_display()
        cls.init_fonts()
        cls.restore_bg(bg)
        cls.clear("")
        cls.present()

    @classmethod
    def init_fonts(cls):
        cls.fonts = {
            purpose: cls._load_font(purpose)
            for purpose in FontPurpose
        }

    @classmethod
    def _load_font(cls, font_purpose):
        font_path = Theme.get_font(font_purpose)
        font_size = Theme.get_font_size(font_purpose)

        try:
            font = pygame.font.Font(font_path, font_size)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Could not load font {font_path}: {e}")
            raise RuntimeError(f"Could not load font {font_path}: {e}")

        # Get line height - pygame uses get_height()
        line_height = font.get_height()

        return LoadedFont(font, line_height, font_path)

    @classmethod
    def _unload_bg_surface(cls):
        if cls.background_surface:
            cls.background_surface = None

    @classmethod
    def restore_bg(cls, bg=None):
        if bg is not None:
            cls.set_new_bg(bg, is_custom_theme_background=True)
        else:
            cls.set_new_bg(Theme.background(), is_custom_theme_background=False)

    @classmethod
    def set_new_bg(cls, bg_path, is_custom_theme_background, retry=True):
        if bg_path is not None and bg_path != cls.bg_path:
            cls._unload_bg_surface()
            cls.is_custom_theme_background = is_custom_theme_background
            cls.bg_path = bg_path

            surface = cls.image_load(cls.bg_path)
            if not surface:
                PyUiLogger.get_logger().error(f"Failed to load image: {cls.bg_path}")
                return

            cls.background_surface = surface

            if not cls.background_surface:
                if retry:
                    PyUiLogger.get_logger().info("Retrying bg surface")
                    cls._text_surface_cache.clear_cache()
                    cls._image_surface_cache.clear_cache()
                    cls.bg_path = None
                    cls.set_new_bg(bg_path, is_custom_theme_background, retry=False)
                else:
                    PyUiLogger.get_logger().error("Failed to create bg surface")
        elif bg_path is None:
            PyUiLogger.get_logger().error(f"Background path none")

    @classmethod
    def set_page_bg(cls, page_bg):
        background = Theme.background(page_bg)
        if background is not None and os.path.exists(background):
            cls.set_new_bg(background, is_custom_theme_background=True)

    @classmethod
    def set_selected_tab(cls, tab):
        cls.top_bar.set_selected_tab(tab)

    @classmethod
    def lock_current_image(cls):
        PyUiLogger.get_logger().info("Locking current image as background")
        if cls.bg_canvas:
            cls.bg_canvas = None

        # Copy render_canvas to bg_canvas
        cls.bg_canvas = cls.render_canvas.copy()
        cls.render_canvas = pygame.Surface((cls._screen_width, cls._screen_height))
        cls.render_canvas.blit(cls.bg_canvas, (0, 0))

    @classmethod
    def unlock_current_image(cls):
        PyUiLogger.get_logger().warning("Unlocking current image as background")
        if cls.bg_canvas:
            cls.bg_canvas = None

    @classmethod
    def clear(cls,
              top_bar_text,
              hide_top_bar_icons=False,
              bottom_bar_text=None,
              render_bottom_bar_icons_and_images=True,
              force_top_and_bottom_bar=False):
        cls.top_bar_text = top_bar_text

        # Render background
        if cls.is_custom_theme_background:
            cls.render_image(cls.bg_path, 0, 0, RenderMode.TOP_LEFT_ALIGNED,
                           cls._screen_width, cls._screen_height, ResizeType.ZOOM)
        elif cls.bg_canvas is not None:
            cls.render_canvas.blit(cls.bg_canvas, (0, 0))
        elif cls.background_surface is not None:
            # Scale background to screen size if needed
            if cls.background_surface.get_size() != (cls._screen_width, cls._screen_height):
                scaled_bg = pygame.transform.scale(cls.background_surface,
                                                   (cls._screen_width, cls._screen_height))
                cls.render_canvas.blit(scaled_bg, (0, 0))
            else:
                cls.render_canvas.blit(cls.background_surface, (0, 0))
        else:
            PyUiLogger.get_logger().warning("No background surface to render")

        if not Theme.render_top_and_bottom_bar_last() or force_top_and_bottom_bar:
            cls.top_bar.render_top_bar(cls.top_bar_text, hide_top_bar_icons)
            cls.bottom_bar.render_bottom_bar(bottom_bar_text,
                                            render_bottom_bar_icons_and_images=render_bottom_bar_icons_and_images)

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
    def _render_surface(cls, x, y, surface, render_mode: RenderMode, surface_id,
                       scale_width=None, scale_height=None, crop_w=None, crop_h=None,
                       resize_type=ResizeType.FIT, alpha=None):
        # If resize_type is none set it to fit for now
        if resize_type is None:
            resize_type = ResizeType.FIT

        orig_w = surface.get_width()
        orig_h = surface.get_height()
        render_w, render_h = cls._calculate_scaled_width_and_height(orig_w, orig_h, scale_width, scale_height, resize_type)

        # Adjust position based on render mode
        adj_x = x
        adj_y = y

        # Handle alpha
        if alpha is not None:
            surface = surface.copy()
            surface.set_alpha(alpha)

        if resize_type == ResizeType.ZOOM and scale_width and scale_height:
            # Scale surface
            scaled_surface = pygame.transform.scale(surface, (render_w, render_h))

            # Calculate source rect for cropping
            src_w = scale_width
            src_h = scale_height

            if YRenderOption.CENTER == render_mode.y_mode:
                adj_y = y - (scale_height or render_h) // 2
                src_y = max(0, (render_h - src_h) // 2)
            elif YRenderOption.BOTTOM == render_mode.y_mode:
                adj_y = y - (scale_height or render_h)
                src_y = max(0, (render_h - src_h))
            elif YRenderOption.TOP == render_mode.y_mode:
                src_y = 0
            else:
                src_y = max(0, (render_h - src_h) // 2)

            if XRenderOption.CENTER == render_mode.x_mode:
                adj_x = x - (scale_width or render_w) // 2
                src_x = max(0, (render_w - src_w) // 2)
            elif XRenderOption.RIGHT == render_mode.x_mode:
                adj_x = x - (scale_width or render_w)
                src_x = max(0, render_w - src_w)
            elif XRenderOption.LEFT == render_mode.x_mode:
                src_x = 0
            else:
                src_x = max(0, (render_w - src_w) // 2)

            adj_x = int(adj_x)
            adj_y = int(adj_y)

            # Blit from scaled surface with subsurface
            src_rect = pygame.Rect(src_x, src_y, min(src_w, render_w), min(src_h, render_h))
            cls.render_canvas.blit(scaled_surface, (adj_x, adj_y), src_rect)

            return scale_width, scale_height
        else:
            # Adjust position
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

            # Handle cropping or regular draw
            if crop_w is None and crop_h is None:
                # Scale if needed
                if render_w != orig_w or render_h != orig_h:
                    scaled_surface = pygame.transform.scale(surface, (render_w, render_h))
                    cls.render_canvas.blit(scaled_surface, (adj_x, adj_y))
                else:
                    cls.render_canvas.blit(surface, (adj_x, adj_y))
            else:
                if crop_w is None or crop_w > orig_w:
                    crop_w = orig_w
                if crop_h is None or crop_h > orig_h:
                    crop_h = orig_h

                src_rect = pygame.Rect(0, 0, crop_w, crop_h)
                cls.render_canvas.blit(surface, (adj_x, adj_y), src_rect)

            return render_w, render_h

    @classmethod
    def log_error_and_clear_cache_image(cls, image_path=None):
        err_msg = str(pygame.get_error()) if pygame.get_error() else "Unknown error"
        PyUiLogger.get_logger().warning(f"Pygame Error received on loading {image_path} : {err_msg}")

        if any(keyword in err_msg for keyword in cls._problematic_image_keywords):
            if image_path is not None:
                cls._problematic_images.add(image_path)
                PyUiLogger.get_logger().warning(f"Marking as image to permanently stop trying to load: {image_path}")

            return False
        else:
            PyUiLogger.get_logger().warning(f"Clearing cache : {err_msg}")
            cls._text_surface_cache.clear_cache()
            cls._image_surface_cache.clear_cache()
            return True

    @classmethod
    def log_error_and_clear_cache_text(cls, text, purpose):
        err_msg = str(pygame.get_error()) if pygame.get_error() else "Unknown error"

        if not (any(keyword in err_msg for keyword in cls._problematic_image_keywords)):
            PyUiLogger.get_logger().warning(f"Pygame Error received on loading {text} w/ purpose {purpose}")
            PyUiLogger.get_logger().warning(f"Clearing cache : {err_msg}")
            cls._text_surface_cache.clear_cache()
            cls._image_surface_cache.clear_cache()
            return True

        return False

    @classmethod
    def render_text(cls, text, x, y, color, purpose: FontPurpose, render_mode=RenderMode.TOP_LEFT_ALIGNED,
                    crop_w=None, crop_h=None, alpha=None):
        text = Display.split_message(text, purpose, clip_to_device_width=False)[0]
        if text is None or len(text) == 0:
            return 0, 0

        loaded_font = cls.fonts[purpose]
        cache: CachedTextSurface = cls._text_surface_cache.get_surface(text, purpose, color)
        cached = True

        if cache and alpha is None:
            surface = cache.surface
        else:
            # Render text with pygame
            try:
                surface = loaded_font.font.render(text, True, color)
            except Exception as e:
                if not cls.log_error_and_clear_cache_text(text, purpose):
                    return 0, 0
                try:
                    surface = loaded_font.font.render(text, True, color)
                except Exception as e:
                    PyUiLogger.get_logger().error(f"Failed to render text surface for {text}: {e}")
                    return 0, 0

            if not surface:
                PyUiLogger.get_logger().error(f"Failed to render text surface for {text}")
                return 0, 0

            if alpha is None:
                cached = cls._text_surface_cache.add_surface(text, purpose, color, surface)

        w, h = cls._render_surface(
            x=x,
            y=y,
            surface=surface,
            render_mode=render_mode,
            surface_id=text,
            crop_w=crop_w,
            crop_h=crop_h,
            alpha=alpha)

        return w, h

    @classmethod
    def render_text_centered(cls, text, x, y, color, purpose: FontPurpose):
        return cls.render_text(text, x, y, color, purpose, RenderMode.TOP_CENTER_ALIGNED)

    @classmethod
    def image_load(cls, image_path):
        try:
            return pygame.image.load(image_path)
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Failed to load image {image_path}: {e}")
            return None

    @classmethod
    def render_image(cls, image_path: str, x: int, y: int, render_mode=RenderMode.TOP_LEFT_ALIGNED,
                    target_width=None, target_height=None, resize_type=None, crop_w=None, crop_h=None):
        if image_path is None or image_path in cls._problematic_images:
            return 0, 0

        cache: CachedImageSurface = cls._image_surface_cache.get_surface(image_path)
        cached = True

        if cache:
            surface = cache.surface
        else:
            surface = cls.image_load(image_path)

            if not surface:
                if not cls.log_error_and_clear_cache_image(image_path):
                    return 0, 0
                surface = cls.image_load(image_path)
                if not surface:
                    PyUiLogger.get_logger().error(f"Failed to load image: {image_path}")
                    return 0, 0

            surface_width = surface.get_width()
            surface_height = surface.get_height()

            if surface_width > Device.get_device().max_texture_width() or surface_height > Device.get_device().max_texture_height():
                PyUiLogger.get_logger().warning(
                    f"Image is too large to render ({surface_width} x {surface_height} with max of {Device.get_device().max_texture_width()} x {Device.get_device().max_texture_height()}). Skipping {image_path}\n"
                )
                cls._problematic_images.add(image_path)
                return 0, 0

            cached = cls._image_surface_cache.add_surface(image_path, surface)

        w, h = cls._render_surface(x=x,
                                   y=y,
                                   surface=surface,
                                   render_mode=render_mode,
                                   scale_width=target_width,
                                   scale_height=target_height,
                                   resize_type=resize_type,
                                   surface_id=image_path,
                                   crop_w=crop_w, crop_h=crop_h)

        if not cached:
            PyUiLogger.get_logger().info(f"Not caching {image_path}. Image cache size is {cls._image_surface_cache.size()}")

        return w, h

    @classmethod
    def render_image_centered(cls, image_path: str, x: int, y: int, target_width=None, target_height=None):
        return cls.render_image(image_path, x, y, RenderMode.TOP_CENTER_ALIGNED, target_width, target_height)

    @classmethod
    def render_box(cls, color, x, y, w, h):
        pygame.draw.rect(cls.render_canvas, color, (x, y, w, h))

    @classmethod
    def get_line_height(cls, purpose: FontPurpose):
        return cls.fonts[purpose].line_height

    @classmethod
    def scale_texture_to_fit(cls, src_surface: pygame.Surface, target_width: int, target_height: int) -> pygame.Surface:
        src_w = src_surface.get_width()
        src_h = src_surface.get_height()

        scale = min(target_width / src_w, target_height / src_h)
        new_width = int(src_w * scale)
        new_height = int(src_h * scale)

        offset_x = (target_width - new_width) // 2
        offset_y = (target_height - new_height) // 2

        # Create new surface
        scaled_surface = pygame.Surface((target_width, target_height))
        scaled_surface.fill((0, 0, 0))

        # Scale and blit
        temp_scaled = pygame.transform.scale(src_surface, (new_width, new_height))
        scaled_surface.blit(temp_scaled, (offset_x, offset_y))

        return scaled_surface

    FADE_DURATION_MS = 96  # 0.25 seconds

    @classmethod
    def fade_transition(cls, surface1, surface2):
        """Fade transition between two surfaces"""
        TARGET_FRAME_MS = 16
        start_time = pygame.time.get_ticks()

        # Create a copy of surface2 for alpha blending
        fading_surface = surface2.copy()

        while True:
            frame_start = pygame.time.get_ticks()

            now = pygame.time.get_ticks()
            elapsed = now - start_time
            alpha = int(255 * (elapsed / cls.FADE_DURATION_MS))
            if alpha > 255:
                alpha = 255

            # Set alpha on fading surface
            fading_surface.set_alpha(alpha)

            # Composite to screen
            cls.screen.blit(surface1, (0, 0))
            cls.screen.blit(fading_surface, (0, 0))
            pygame.display.flip()

            if alpha == 255:
                break

            # Frame pacing
            frame_time = pygame.time.get_ticks() - frame_start
            delay = TARGET_FRAME_MS - frame_time
            if delay > 0:
                pygame.time.wait(delay)

    @classmethod
    def rotate_canvas(cls) -> pygame.Surface:
        """Rotates render_canvas by device rotation angle"""
        angle = Device.get_device().screen_rotation()

        if angle == 0:
            return cls.render_canvas

        # Pygame rotation is counter-clockwise, so negate for clockwise
        rotated = pygame.transform.rotate(cls.render_canvas, -angle)
        return rotated

    @classmethod
    def present(cls, fade=False):
        if Theme.render_top_and_bottom_bar_last():
            cls.top_bar.render_top_bar(cls.top_bar_text)
            cls.bottom_bar.render_bottom_bar()

        if Device.get_device().should_scale_screen():
            scaled_canvas = cls.scale_texture_to_fit(cls.render_canvas,
                                                     Device.get_device().output_screen_width(),
                                                     Device.get_device().output_screen_height())
            cls.screen.blit(scaled_canvas, (0, 0))
        elif 0 == Device.get_device().screen_rotation():
            if fade and cls.bg_canvas:
                cls.fade_transition(cls.bg_canvas, cls.render_canvas)
            else:
                cls.screen.blit(cls.render_canvas, (0, 0))
        else:
            rotated_surface = cls.rotate_canvas()
            if rotated_surface is not None:
                # Center the rotated surface if dimensions changed
                offset_x = (cls._screen_width - rotated_surface.get_width()) // 2
                offset_y = (cls._screen_height - rotated_surface.get_height()) // 2
                cls.screen.blit(rotated_surface, (offset_x, offset_y))

        pygame.display.flip()
        Device.get_device().post_present_operations()

    @classmethod
    def get_top_bar_height(cls, force_include_top_bar=True):
        return 0 if Theme.ignore_top_and_bottom_bar_for_layout() and not force_include_top_bar else cls.top_bar.get_top_bar_height()

    @classmethod
    def get_bottom_bar_height(cls):
        return 0 if Theme.ignore_top_and_bottom_bar_for_layout() else cls.bottom_bar.get_bottom_bar_height()

    @classmethod
    def get_usable_screen_height(cls, force_include_top_bar=False):
        return cls._screen_height if Theme.ignore_top_and_bottom_bar_for_layout() and not force_include_top_bar else cls._screen_height - cls.get_bottom_bar_height() - cls.get_top_bar_height()

    @classmethod
    def get_center_of_usable_screen_height(cls, force_include_top_bar=False):
        return ((cls._screen_height - cls.get_bottom_bar_height() - cls.get_top_bar_height(force_include_top_bar)) // 2) + cls.get_top_bar_height(force_include_top_bar)

    @classmethod
    def get_image_dimensions(cls, img):
        if img is None:
            return 0, 0

        surface = cls.image_load(img)
        if not surface:
            return 0, 0
        width, height = surface.get_width(), surface.get_height()
        return width, height

    _cached_space_dimensions = None

    @classmethod
    def get_space_dimensions(cls, font_purpose=FontPurpose.LIST):
        """Returns the width and height of a space character for the given font."""
        if cls._cached_space_dimensions is None:
            cls._cached_space_dimensions = cls.get_text_dimensions(font_purpose, " ")
        return cls._cached_space_dimensions

    @classmethod
    def get_text_dimensions(cls, purpose, text="A"):
        font = cls.fonts[purpose].font
        w, h = font.size(text)
        return int(w * Device.get_device().get_text_width_measurement_multiplier()), h

    @classmethod
    def add_index_text(cls, index, total, force_include_index=False, letter=None):
        if force_include_index or Theme.show_index_text():
            y_padding = max(5, cls.get_bottom_bar_height() // 4)
            y_value = cls._screen_height - y_padding
            x_padding = 10

            x_offset = cls._screen_width - x_padding
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

            x_offset -= index_text_w + x_padding
            if letter is not None:
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
            if Device.get_device().get_guaranteed_safe_max_text_char_count() >= len(line):
                return False
            text_w, text_h = Display.get_text_dimensions(font_purpose, line)
            max_width = Device.get_device().max_texture_width()
            if clip_to_device_width:
                max_width = min(max_width, cls._screen_width)
            max_width = max_width - int(10 * cls._screen_height / 480)
            return text_w > max_width
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Error checking text length: {e}")
            return False

    @classmethod
    def split_message(cls, message: str, font_purpose, clip_to_device_width) -> list:
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
    def display_message_multiline(cls, split_message, duration_ms=0):
        Display.clear("")
        cls.write_message_multiline(split_message, cls._screen_height // 2)
        Display.present()
        # Sleep for the specified duration in milliseconds
        time.sleep(duration_ms / 1000)

    @classmethod
    def write_message_multiline(cls, split_message, middle_height):
        text_w, text_h = Display.get_text_dimensions(FontPurpose.LIST, "W")

        height_per_line = text_h + int(5 * cls._screen_height / 480)
        starting_height = middle_height - (len(split_message) * height_per_line) // 2

        for i, line in enumerate(split_message):
            Display.render_text_centered(f"{line}", cls._screen_width // 2, starting_height + i * height_per_line,
                                        Theme.text_color(FontPurpose.LIST), purpose=FontPurpose.LIST)

    @classmethod
    def write_message_multiline_starting_height_specified(cls, split_message, starting_height):
        text_w, text_h = Display.get_text_dimensions(FontPurpose.LIST, "W")

        height_per_line = text_h + int(5 * cls._screen_height / 480)

        for i, line in enumerate(split_message):
            Display.render_text_centered(f"{line}", cls._screen_width // 2, starting_height + i * height_per_line,
                                        Theme.text_color(FontPurpose.LIST), purpose=FontPurpose.LIST)

    @classmethod
    def display_message(cls, message, duration_ms=0):
        split_message = Display.split_message(message, FontPurpose.LIST, clip_to_device_width=True)
        cls.display_message_multiline(split_message, duration_ms)

    @classmethod
    def display_image(cls, image_path, duration_ms=0):
        Display.clear("")
        Display.render_image(image_path, cls._screen_width // 2, cls._screen_height // 2, RenderMode.MIDDLE_CENTER_ALIGNED)
        Display.present()
        # Sleep for the specified duration in milliseconds
        time.sleep(duration_ms / 1000)
