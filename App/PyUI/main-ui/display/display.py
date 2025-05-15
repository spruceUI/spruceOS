import time
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
from devices.device import Device
from utils.logger import PyUiLogger

class Display:
    def __init__(self, theme: Theme, device: Device):
        self.debug = False
        self.theme = theme
        self.device = device
        self._init_display()
        self.init_fonts()
        self.bg_canvas = None
        self.render_canvas = sdl2.SDL_CreateTexture(self.renderer.renderer,
                                        sdl2.SDL_PIXELFORMAT_ARGB8888,
                                        sdl2.SDL_TEXTUREACCESS_TARGET,
                                        self.device.screen_width, self.device.screen_height)
        PyUiLogger.get_logger().info(f"sdl2.SDL_GetError() : {sdl2.SDL_GetError()}")
        sdl2.SDL_SetRenderTarget(self.renderer.renderer, self.render_canvas)
        PyUiLogger.get_logger().info(f"sdl2.SDL_GetError() : {sdl2.SDL_GetError()}")
        self.bg_path = ""
        self._check_for_bg_change()
        self.top_bar = TopBar(self,device,theme)
        self.bottom_bar = BottomBar(self,device,theme)
        self.clear("init")
        self.present()


    def init_fonts(self):
        self.fonts = {
            purpose: self._load_font(purpose)
            for purpose in FontPurpose
        }        


    def _init_display(self):
        sdl2.ext.init(controller=True)
        sdl2.SDL_InitSubSystem(sdl2.SDL_INIT_GAMECONTROLLER)
        display_mode = sdl2.SDL_DisplayMode()
        if sdl2.SDL_GetCurrentDisplayMode(0, display_mode) != 0:
            PyUiLogger.get_logger().error("Failed to get display mode, using fallback 640x480")
            width, height = self.device.screen_width(), self.device.screen_height()
        else:
            width, height = display_mode.w, display_mode.h
            PyUiLogger.get_logger().info(f"Display size: {width}x{height}")

        self.window = sdl2.ext.Window("Minimal SDL2 GUI", size=(width, height), flags=sdl2.SDL_WINDOW_FULLSCREEN)
        self.window.show()

        sdl2.SDL_SetHint(sdl2.SDL_HINT_RENDER_SCALE_QUALITY, b"2")
        # Use default renderer flags
        self.renderer = sdl2.ext.Renderer(self.window, flags=sdl2.SDL_RENDERER_ACCELERATED)

    def deinit_display(self):
        if(self.renderer is not None):
            sdl2.SDL_DestroyRenderer(self.renderer.sdlrenderer)
            self.renderer = None
        if(self.window is not None):
            sdl2.SDL_DestroyWindow(self.window.window)
            self.window = None
        self.deinit_fonts()
        self._unload_bg_texture()
        sdl2.SDL_QuitSubSystem(sdl2.SDL_INIT_VIDEO)

    def deinit_fonts(self):
        for loaded_font in self.fonts.values():
            sdl2.sdlttf.TTF_CloseFont(loaded_font.font)
        self.fonts.clear()

    def reinitialize(self):
        self.deinit_display()
        self._unload_bg_texture()
        self._init_display()
        self.init_fonts()
        self._load_bg_texture()
        self.clear("reinitialize")
        self.present()

    def _unload_bg_texture(self):
        if hasattr(self, 'background_texture') and self.background_texture:
            sdl2.SDL_DestroyTexture(self.background_texture)
            PyUiLogger.get_logger().debug("Destroying bg texture")

    def _load_bg_texture(self):
        self.bg_path = self.theme.background
        # Load the image into an SDL_Surface
        surface = sdl2.sdlimage.IMG_Load(self.bg_path.encode('utf-8'))
        if not surface:
            PyUiLogger.get_logger().error(f"Failed to load image: {self.bg_path}")
        self.background_texture = sdl2.SDL_CreateTextureFromSurface(self.renderer.renderer, surface)
        if not self.background_texture:
            sdl2.SDL_FreeSurface(surface)
            PyUiLogger.get_logger().error(f"Failed to create texture from surface")

    def _check_for_bg_change(self):
        if self.bg_path != self.theme.background:
            self._unload_bg_texture()
            self._load_bg_texture()

    def _load_font(self, font_purpose):
        if sdl2.sdlttf.TTF_Init() == -1:
            raise RuntimeError("Failed to initialize SDL_ttf")

        # Load the TTF font
        # font_path = "/mnt/SDCARD/spruce/Font Files/Noto.ttf"
        font_path = self.theme.get_font(font_purpose)
        font_size = self.theme.get_font_size(font_purpose)
        
        font = sdl2.sdlttf.TTF_OpenFont(font_path.encode('utf-8'), font_size)
        if not font:
            raise RuntimeError(f"Could not load font {font_path} : {sdl2.sdlttf.TTF_GetError().decode('utf-8')}")
        line_height = sdl2.sdlttf.TTF_FontHeight(font)
        return LoadedFont(font,line_height)
        

    def lock_current_image_as_bg(self):
        self.bg_canvas = self.render_canvas
        self.render_canvas = sdl2.SDL_CreateTexture(self.renderer.renderer,
                                sdl2.SDL_PIXELFORMAT_ARGB8888,
                                sdl2.SDL_TEXTUREACCESS_TARGET,
                                self.device.screen_width, self.device.screen_height)
        sdl2.SDL_SetRenderTarget(self.renderer.renderer, self.render_canvas)
        sdl2.SDL_RenderCopy(self.renderer.sdlrenderer, self.bg_canvas, None, None)

    def unlock_current_image_as_bg(self):
        sdl2.SDL_DestroyTexture(self.bg_canvas)
        self.bg_canvas = None

    def clear(self, screen):
        self.screen = screen       
        self._check_for_bg_change()

        if(self.bg_canvas is not None):
            sdl2.SDL_RenderCopy(self.renderer.sdlrenderer, self.bg_canvas, None, None)
        elif(self.background_texture is not None):
            sdl2.SDL_RenderCopy(self.renderer.sdlrenderer, self.background_texture, None, None)

        if(not self.theme.render_top_and_bottom_bar_last()):
            self.top_bar.render_top_bar(self.screen)
            self.bottom_bar.render_bottom_bar()

    def _calculate_scaled_width_and_height(self, orig_w, orig_h, target_width, target_height):
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

    def _log(self, msg):
        if(self.debug):
            PyUiLogger.get_logger().info(msg)

    def _render_surface_texture(self, x, y, texture, surface, render_mode : RenderMode, scale_width=None, scale_height=None, debug="",
                                crop_w=None, crop_h=None):
        render_w, render_h = self._calculate_scaled_width_and_height(surface.contents.w, surface.contents.h, scale_width, scale_height)

        # Adjust position based on render mode
        adj_x = x
        adj_y = y
        
        if(XRenderOption.CENTER == render_mode.x_mode):
            adj_x = x - render_w // 2
        elif(XRenderOption.RIGHT == render_mode.x_mode):
            adj_x = x - render_w

        if(YRenderOption.CENTER == render_mode.y_mode):
            adj_y = y - render_h // 2
        elif(YRenderOption.BOTTOM == render_mode.y_mode):
            adj_y = y - render_h

        adj_x = int(adj_x)
        adj_y = int(adj_y)

        # Create destination rect with adjusted position and scaled size
        if(crop_w is None and crop_h is None):            
            rect = sdl2.SDL_Rect(adj_x, adj_y, render_w, render_h)
            self._log(f"Rendered {debug} at {adj_x}, {adj_y} with dimenons {render_w}x{render_h}")
            # Copy the texture to the renderer
            sdl2.SDL_RenderCopy(self.renderer.renderer, texture, None, rect)
        else:
            if crop_w is None or crop_w > surface.contents.w:
                crop_w = surface.contents.w
            if crop_h is None or crop_h > surface.contents.h:
                crop_h = surface.contents.h

            # Source rectangle: crop from top-left of texture (unscaled)
            src_rect = sdl2.SDL_Rect(0, 0, crop_w, crop_h)

            # Destination rectangle: where to draw on screen, scaled
            dst_rect = sdl2.SDL_Rect(
                adj_x,
                adj_y,
                int(crop_w),
                int(crop_h)
            )

            # Draw the cropped and scaled texture
            sdl2.SDL_RenderCopy(self.renderer.renderer, texture, src_rect, dst_rect)

        # Clean up
        sdl2.SDL_DestroyTexture(texture)
        sdl2.SDL_FreeSurface(surface)

        return render_w, render_h
    
    def render_text(self,text, x, y, color, purpose : FontPurpose, render_mode = RenderMode.TOP_LEFT_ALIGNED,
                    crop_w=None, crop_h=None):
        # Create an SDL_Color
        sdl_color = sdl2.SDL_Color(color[0], color[1], color[2])
        
        # Render the text to a surface
        surface = sdl2.sdlttf.TTF_RenderUTF8_Blended(self.fonts[purpose].font, text.encode('utf-8'), sdl_color)
        if not surface:
            PyUiLogger.get_logger().error(f"Failed to render text surface for {text}: {sdl2.sdlttf.TTF_GetError().decode('utf-8')}")
            return 0,0
        
        # Create a texture from the surface
        texture = sdl2.SDL_CreateTextureFromSurface(self.renderer.renderer, surface)
        if not texture:
            sdl2.SDL_FreeSurface(surface)
            PyUiLogger.get_logger().error(f"Failed to create texture from surface {text}: {sdl2.sdlttf.TTF_GetError().decode('utf-8')}")
            return 0,0

        return self._render_surface_texture(x, y, texture, surface, render_mode, debug=text, crop_w=crop_w, crop_h=crop_h)

    def render_text_centered(self,text, x, y, color, purpose : FontPurpose):
        self.render_text(text, x, y, color, purpose, RenderMode.TOP_CENTER_ALIGNED)

    def render_image(self, image_path: str, x: int, y: int, render_mode = RenderMode.TOP_LEFT_ALIGNED, target_width=None, target_height=None):
        # Load the image into an SDL_Surface
        surface = sdl2.sdlimage.IMG_Load(image_path.encode('utf-8'))
        if not surface:
            PyUiLogger.get_logger().error(f"Failed to load image: {image_path}")
            return 0,0

        # Create a texture from the surface
        texture = sdl2.SDL_CreateTextureFromSurface(self.renderer.renderer, surface)
        if not texture:
            sdl2.SDL_FreeSurface(surface)
            PyUiLogger.get_logger().error(f"Failed to create texture from surface")
            return 0,0

        sdl2.SDL_SetTextureBlendMode(texture, sdl2.SDL_BLENDMODE_BLEND)
        return self._render_surface_texture(x, y, texture, surface, render_mode, target_width, target_height, debug=image_path)
    
    def render_image_centered(self, image_path: str, x: int, y: int, target_width=None, target_height=None):
        return self.render_image(image_path,x,y,RenderMode.TOP_CENTER_ALIGNED, target_width, target_height)

    def render_box(self, color, x, y, w, h):
        # RGB (0,0,0) for black, Alpha 255 (fully opaque)
        sdl2.SDL_SetRenderDrawColor(self.renderer.renderer, color[0], color[1], color[2], 255)  
        # Define the rectangle's position and size (320x240 at position 160x120)
        rect = sdl2.SDL_Rect(x, y, w, h)
        # Draw the filled rectangle
        sdl2.SDL_RenderFillRect(self.renderer.renderer, rect)

    def get_line_height(self, purpose : FontPurpose):
        return self.fonts[purpose].line_height
        
    def scale_texture_to_fit(self, src_texture: sdl2.SDL_Texture, target_width: int, target_height: int) -> sdl2.SDL_Texture:
        # Get the original size of the texture
        width = sdl2.c_int()
        height = sdl2.c_int()
        sdl2.SDL_QueryTexture(src_texture, None, None, width, height)

        src_w = width.value
        src_h = height.value

        # Compute scale factor to fit while preserving aspect ratio
        scale_w = target_width / src_w
        scale_h = target_height / src_h
        scale = min(scale_w, scale_h)

        # Calculate scaled size
        new_width = int(src_w * scale)
        new_height = int(src_h * scale)

        # Center the scaled image in the target canvas
        offset_x = (target_width - new_width) // 2
        offset_y = (target_height - new_height) // 2

        # Create the target texture (canvas) to render onto
        scaled_texture = sdl2.SDL_CreateTexture(
            self.renderer.sdlrenderer,
            sdl2.SDL_PIXELFORMAT_ARGB8888,
            sdl2.SDL_TEXTUREACCESS_TARGET,
            target_width,
            target_height
        )

        if not scaled_texture:
            raise RuntimeError("Failed to create scaled texture")

        # Save current render target
        old_target = sdl2.SDL_GetRenderTarget(self.renderer.sdlrenderer)

        # Set blend modes (if needed)
        sdl2.SDL_SetTextureBlendMode(src_texture, sdl2.SDL_BLENDMODE_BLEND)
        sdl2.SDL_SetTextureBlendMode(scaled_texture, sdl2.SDL_BLENDMODE_BLEND)

        # Render to the new texture
        sdl2.SDL_SetRenderTarget(self.renderer.sdlrenderer, scaled_texture)

        # Clear the canvas with transparent black
        sdl2.SDL_SetRenderDrawColor(self.renderer.sdlrenderer, 0, 0, 0, 0)
        sdl2.SDL_RenderClear(self.renderer.sdlrenderer)

        # Destination rect for the scaled and centered texture
        dest_rect = sdl2.SDL_Rect(offset_x, offset_y, new_width, new_height)

        # Render the source into the new canvas
        sdl2.SDL_RenderCopy(self.renderer.sdlrenderer, src_texture, None, dest_rect)

        # Restore previous render target
        sdl2.SDL_SetRenderTarget(self.renderer.sdlrenderer, old_target)

        return scaled_texture

        
    def present(self):
        if(self.theme.render_top_and_bottom_bar_last()):
            self.top_bar.render_top_bar(self.screen)
            self.bottom_bar.render_bottom_bar()

        sdl2.SDL_SetRenderTarget(self.renderer.renderer, None)

        if(self.device.should_scale_screen()):
            scaled_canvas = self.scale_texture_to_fit(self.render_canvas, self.device.output_screen_width, self.device.output_screen_height)
            sdl2.SDL_RenderCopy(self.renderer.sdlrenderer, scaled_canvas, None, None)
            sdl2.SDL_DestroyTexture(scaled_canvas)  # Clean up temporary scaled texture
        else:
            sdl2.SDL_RenderCopy(self.renderer.sdlrenderer, self.render_canvas, None, None)

        sdl2.SDL_SetRenderTarget(self.renderer.renderer, self.render_canvas)

        self.renderer.present()

    def get_top_bar_height(self):
        if(self.theme.ignore_top_and_bottom_bar_for_layout()):
            return 0
        else:
            return self.top_bar.get_top_bar_height()
    
    def get_bottom_bar_height(self):
        if(self.theme.ignore_top_and_bottom_bar_for_layout()):
            return 0
        else:
            return self.bottom_bar.get_bottom_bar_height()
    
    def get_usable_screen_height(self):
        return self.device.screen_height - self.get_bottom_bar_height() - self.get_top_bar_height()
    
    def get_center_of_usable_screen_height(self):
        return ((self.device.screen_height - self.get_bottom_bar_height() - self.get_top_bar_height()) // 2) + self.get_top_bar_height() 

    def get_image_dimensions(self, img):        
        surface = sdl2.sdlimage.IMG_Load(img.encode('utf-8'))
        if not surface:
            return 0,0
        width = surface.contents.w
        height = surface.contents.h
        sdl2.SDL_FreeSurface(surface)
        return width, height
    
    def get_text_dimensions(self, purpose, text = "A"):
              
        sdl_color = sdl2.SDL_Color(0,0,0)
        surface = sdl2.sdlttf.TTF_RenderUTF8_Blended(self.fonts[purpose].font, text.encode('utf-8'), sdl_color)
        if not surface:
            return 0,0
        
        width = surface.contents.w
        height = surface.contents.h
        sdl2.SDL_FreeSurface(surface)
        return width, height


    def add_index_text(self, index, total):
        # TODO don't hard code these
        # TODO why is it divide by 4 and not divide by 2?
        y_padding = max(5,self.get_bottom_bar_height() // 4)
        y_value = self.device.screen_height - y_padding
        x_padding = 10 

        total_text_x = self.device.screen_width - x_padding
        total_text_w, total_text_h = self.render_text(
            str(total),
            total_text_x,
            y_value, 
            self.theme.text_color(FontPurpose.LIST_TOTAL), 
            FontPurpose.LIST_TOTAL, 
            RenderMode.BOTTOM_RIGHT_ALIGNED)

        index_text_x = self.device.screen_width - x_padding - total_text_w
        index_text_w, index_text_y = self.render_text(
            str(index)+"/",
            index_text_x,
            y_value, 
            self.theme.text_color(FontPurpose.LIST_INDEX), 
            FontPurpose.LIST_INDEX, 
            RenderMode.BOTTOM_RIGHT_ALIGNED)

    def get_current_top_bar_title(self):
        return self.top_bar.get_current_title()