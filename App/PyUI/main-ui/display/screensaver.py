import time
import datetime
import os
import sdl2
import sdl2.sdlimage
import sdl2.sdlttf

from devices.device import Device
from display.font_purpose import FontPurpose
from display.render_mode import RenderMode
from themes.theme import Theme
from utils.logger import PyUiLogger


class ScreenSaver:
    _animation_path = None
    _animation = None
    _animation_frame = 0
    _animation_next_time = 0

    @classmethod
    def render(cls):
        try:
            renderer = Device.get_device()
            screen_w = renderer.screen_width()
            screen_h = renderer.screen_height()
            from display.display import Display

            cls._render_background(screen_w, screen_h, Display)

            widgets = cls._get_enabled_widgets()
            for widget in widgets:
                cls._render_widget(widget, screen_w, screen_h, Display)

            cls._present_without_bars(Display)
        except Exception as e:
            PyUiLogger.get_logger().error(f"ScreenSaver render error: {e}")

    @classmethod
    def render_if_needed(cls):
        if cls._animation_path and time.time() >= cls._animation_next_time:
            cls.render()

    @classmethod
    def clear_cache(cls):
        cls._clear_animation()

    @classmethod
    def _present_without_bars(cls, Display):
        sdl2.SDL_SetRenderTarget(Display.renderer.renderer, None)

        if Device.get_device().should_scale_screen():
            scaled_canvas = Display.scale_texture_to_fit(
                Display.render_canvas,
                Device.get_device().output_screen_width(),
                Device.get_device().output_screen_height()
            )
            sdl2.SDL_RenderCopy(Display.renderer.sdlrenderer, scaled_canvas, None, None)
            sdl2.SDL_DestroyTexture(scaled_canvas)
        elif Device.get_device().screen_rotation() == 0:
            sdl2.SDL_RenderCopy(Display.renderer.sdlrenderer, Display.render_canvas, None, None)
        else:
            rotated_texture = Display.rotate_canvas()
            if rotated_texture is not None:
                sdl2.SDL_RenderCopy(Display.renderer.sdlrenderer, rotated_texture, None, None)
                sdl2.SDL_DestroyTexture(rotated_texture)

        sdl2.SDL_SetRenderTarget(Display.renderer.renderer, Display.render_canvas)
        Display.renderer.present()
        Device.get_device().post_present_operations()

    @classmethod
    def _render_background(cls, screen_w, screen_h, Display):
        ss = Theme._data.get("screensaver", {})
        bg_image = cls._get_bg_image(ss.get("bgImage", ""))
        overlay_opacity = ss.get("overlayOpacity", 0.3)
        overlay_color = Theme.hex_to_color(ss.get("overlayColor", "#000000"))
        blur = ss.get("blur", 0)
        bg_color = Theme.hex_to_color(ss.get("bgColor", "#000000"))

        if bg_image and os.path.exists(bg_image):
            if bg_image.lower().endswith(".gif"):
                cls._render_gif_background(bg_image, screen_w, screen_h, Display, bg_color)
            else:
                cls._clear_animation()
                cls._render_static_background(bg_image, screen_w, screen_h, Display, bg_color, blur)
        else:
            cls._clear_animation()
            sdl2.SDL_SetRenderDrawColor(Display.renderer.sdlrenderer,
                bg_color[0], bg_color[1], bg_color[2], 255)
            sdl2.SDL_RenderClear(Display.renderer.sdlrenderer)

        if 0 < overlay_opacity <= 1.0:
            alpha = int(overlay_opacity * 255)
            sdl2.SDL_SetRenderDrawBlendMode(Display.renderer.sdlrenderer, sdl2.SDL_BLENDMODE_BLEND)
            sdl2.SDL_SetRenderDrawColor(Display.renderer.sdlrenderer,
                overlay_color[0], overlay_color[1], overlay_color[2], alpha)
            rect = sdl2.SDL_Rect(0, 0, screen_w, screen_h)
            sdl2.SDL_RenderFillRect(Display.renderer.sdlrenderer, rect)

    @classmethod
    def _render_static_background(cls, bg_image, screen_w, screen_h, Display, bg_color, blur):
        surface = sdl2.sdlimage.IMG_Load(bg_image.encode("utf-8"))
        if surface:
            if blur > 0:
                surface = cls._apply_blur(surface, blur)
            texture = sdl2.SDL_CreateTextureFromSurface(Display.renderer.renderer, surface)
            if texture:
                sdl2.SDL_SetTextureBlendMode(texture, sdl2.SDL_BLENDMODE_BLEND)
                src_w = surface.contents.w
                src_h = surface.contents.h
                src = sdl2.SDL_Rect(0, 0, src_w, src_h)
                dst = sdl2.SDL_Rect(0, 0, screen_w, screen_h)
                sdl2.SDL_RenderCopy(Display.renderer.renderer, texture, src, dst)
                sdl2.SDL_DestroyTexture(texture)
            sdl2.SDL_FreeSurface(surface)
        else:
            sdl2.SDL_SetRenderDrawColor(Display.renderer.sdlrenderer,
                bg_color[0], bg_color[1], bg_color[2], 255)
            sdl2.SDL_RenderClear(Display.renderer.sdlrenderer)

    @classmethod
    def _render_gif_background(cls, bg_image, screen_w, screen_h, Display, bg_color):
        if cls._animation_path != bg_image:
            cls._load_animation(bg_image, Display)

        if not cls._animation:
            sdl2.SDL_SetRenderDrawColor(Display.renderer.sdlrenderer,
                bg_color[0], bg_color[1], bg_color[2], 255)
            sdl2.SDL_RenderClear(Display.renderer.sdlrenderer)
            return

        anim = cls._animation.contents
        frame = cls._animation_frame % anim.count
        surface = anim.frames[frame]
        texture = sdl2.SDL_CreateTextureFromSurface(Display.renderer.renderer, surface)
        if not texture:
            return
        sdl2.SDL_SetTextureBlendMode(texture, sdl2.SDL_BLENDMODE_BLEND)
        src = sdl2.SDL_Rect(0, 0, anim.w, anim.h)
        dst = sdl2.SDL_Rect(0, 0, screen_w, screen_h)
        sdl2.SDL_RenderCopy(Display.renderer.renderer, texture, src, dst)
        sdl2.SDL_DestroyTexture(texture)

        delay = anim.delays[frame] if anim.delays else 100
        if delay < 100:
            delay = 100
        cls._animation_frame = (frame + 1) % anim.count
        cls._animation_next_time = time.time() + delay / 1000.0

    @classmethod
    def _load_animation(cls, bg_image, Display):
        cls._clear_animation()
        animation = sdl2.sdlimage.IMG_LoadAnimation(bg_image.encode("utf-8"))
        if not animation:
            return

        cls._animation_path = bg_image
        cls._animation = animation
        cls._animation_frame = 0
        cls._animation_next_time = 0
        anim = animation.contents

    @classmethod
    def _clear_animation(cls):
        if cls._animation:
            sdl2.sdlimage.IMG_FreeAnimation(cls._animation)
        cls._animation = None
        cls._animation_path = None
        cls._animation_frame = 0
        cls._animation_next_time = 0

    @classmethod
    def _get_bg_image(cls, configured_path):
        candidates = []
        if configured_path:
            candidates.append(configured_path)
            if not os.path.isabs(configured_path):
                candidates.append(os.path.join(Theme.get_theme_path(), configured_path))

        candidates.append(os.path.join(Theme.get_theme_path(), "screensaver.gif"))
        candidates.append(os.path.join(Theme.get_theme_path(), "screensaver.png"))
        candidates.append("/mnt/SDCARD/App/PyUI/main-ui/themes/screensaver.gif")
        candidates.append("/mnt/SDCARD/App/PyUI/main-ui/themes/screensaver.png")

        for path in candidates:
            if path and os.path.exists(path):
                return path
        return ""

    @classmethod
    def _apply_blur(cls, surface, radius):
        w = surface.contents.w
        h = surface.contents.h
        fmt = surface.contents.format.contents
        src_pixels = sdl2.SDL_LockSurface(surface)
        if src_pixels == 0:
            return surface

        try:
            pixels = surface.contents.pixels
            pitch = surface.contents.pitch
            bpp = fmt.BytesPerPixel
            temp = sdl2.SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, fmt.format)
            if not temp:
                return surface

            sdl2.SDL_LockSurface(temp)
            try:
                temp_pixels = temp.contents.pixels
                temp_pitch = temp.contents.pitch

                r = min(radius, min(w, h) // 2)
                if r < 1:
                    r = 1

                kernel_size = 2 * r + 1
                for y in range(h):
                    for x in range(w):
                        sum_r, sum_g, sum_b, count = 0, 0, 0, 0
                        for ky in range(-r, r + 1):
                            sy = y + ky
                            if sy < 0 or sy >= h:
                                continue
                            for kx in range(-r, r + 1):
                                sx = x + kx
                                if sx < 0 or sx >= w:
                                    continue
                                offset = sy * pitch + sx * bpp
                                if bpp == 4:
                                    b = pixels[offset]
                                    g = pixels[offset + 1]
                                    rd = pixels[offset + 2]
                                    a = pixels[offset + 3]
                                elif bpp == 3:
                                    b = pixels[offset]
                                    g = pixels[offset + 1]
                                    rd = pixels[offset + 2]
                                    a = 255
                                else:
                                    continue
                                sum_r += rd
                                sum_g += g
                                sum_b += b
                                count += 1
                        if count > 0:
                            avg_r = sum_r // count
                            avg_g = sum_g // count
                            avg_b = sum_b // count
                        else:
                            avg_r, avg_g, avg_b = 0, 0, 0
                        dst_offset = y * temp_pitch + x * bpp
                        if bpp == 4:
                            temp_pixels[dst_offset] = avg_b
                            temp_pixels[dst_offset + 1] = avg_g
                            temp_pixels[dst_offset + 2] = avg_r
                            temp_pixels[dst_offset + 3] = 255
                        elif bpp == 3:
                            temp_pixels[dst_offset] = avg_b
                            temp_pixels[dst_offset + 1] = avg_g
                            temp_pixels[dst_offset + 2] = avg_r
            finally:
                sdl2.SDL_UnlockSurface(temp)
        finally:
            sdl2.SDL_UnlockSurface(surface)

        sdl2.SDL_BlitSurface(temp, None, surface, None)
        sdl2.SDL_FreeSurface(temp)
        return surface

    @classmethod
    def _get_enabled_widgets(cls):
        ss = Theme._data.get("screensaver", {})
        show_clock = ss.get("showClock", True)
        show_date = ss.get("showDate", True)
        show_battery = ss.get("showBattery", True)

        all_widgets = Theme.get_screensaver_widgets()
        enabled = []
        for w in all_widgets:
            if not w.get("enabled", True):
                continue
            wtype = w.get("type", "")
            if wtype == "clock" and not show_clock:
                continue
            if wtype == "date" and not show_date:
                continue
            if wtype == "battery" and not show_battery:
                continue
            enabled.append(w)
        return enabled

    @classmethod
    def _render_widget(cls, widget, screen_w, screen_h, Display):
        wtype = widget.get("type", "")
        x = int(widget.get("x", 0.5) * screen_w)
        y = int(widget.get("y", 0.5) * screen_h)
        font_size = int(widget.get("fontSize", 24))
        color = Theme.hex_to_color(widget.get("color", "#FFFFFF"))
        multiplier = Theme._default_multiplier
        scaled_size = max(12, int(font_size * multiplier))

        if wtype == "clock":
            now = datetime.datetime.now()
            text = now.strftime("%H:%M")
            cls._draw_text(text, x, y, color, scaled_size, Display, center=True, widget=widget)

        elif wtype == "date":
            now = datetime.datetime.now()
            text = now.strftime("%A, %B %d")
            cls._draw_text(text, x, y, color, scaled_size, Display, center=True, widget=widget)

        elif wtype == "battery":
            try:
                percent = Device.get_device().get_battery_percent()
                charging = Device.get_device().get_charge_status()
                from devices.charge.charge_status import ChargeStatus
                symbol = "+" if charging == ChargeStatus.CHARGING else ""
                text = f"{symbol}{percent}%"
                if percent <= 10:
                    color = (255, 80, 80)
                elif percent <= 30:
                    color = (255, 200, 80)
                style = widget.get("style", "percent")
                if style == "bar":
                    cls._draw_battery_bar(percent, x, y, color, screen_w, screen_h, Display)
                elif style == "pill":
                    cls._draw_battery_pill(percent, x, y, color, screen_w, screen_h, Display)
                elif style == "segments":
                    cls._draw_battery_segments(percent, x, y, color, screen_w, screen_h, Display)
                elif style == "blocks":
                    filled = max(0, min(5, int(round(percent / 20))))
                    text = "[" + ("|" * filled).ljust(5, " ") + f"] {percent}%"
                    cls._draw_text(text, x, y, color, scaled_size, Display, center=True, widget=widget)
                else:
                    cls._draw_text(text, x, y, color, scaled_size, Display, center=True, widget=widget)
            except Exception:
                pass

        elif wtype == "text":
            text = widget.get("value", "")
            if text:
                cls._draw_text(text, x, y, color, scaled_size, Display, center=True, widget=widget)

    @classmethod
    def _draw_battery_bar(cls, percent, x, y, color, screen_w, screen_h, Display):
        width = max(80, int(screen_w * 0.11))
        height = max(24, int(screen_h * 0.035))
        left = x - width // 2
        top = y - height // 2
        sdl2.SDL_SetRenderDrawBlendMode(Display.renderer.sdlrenderer, sdl2.SDL_BLENDMODE_BLEND)
        sdl2.SDL_SetRenderDrawColor(Display.renderer.sdlrenderer, color[0], color[1], color[2], 255)
        sdl2.SDL_RenderDrawRect(Display.renderer.sdlrenderer, sdl2.SDL_Rect(left, top, width, height))
        sdl2.SDL_RenderDrawRect(Display.renderer.sdlrenderer, sdl2.SDL_Rect(left + width, top + height // 4, 6, height // 2))
        fill_width = max(0, int((width - 6) * percent / 100))
        if fill_width > 0:
            sdl2.SDL_RenderFillRect(Display.renderer.sdlrenderer, sdl2.SDL_Rect(left + 3, top + 3, fill_width, height - 6))

    @classmethod
    def _draw_battery_pill(cls, percent, x, y, color, screen_w, screen_h, Display):
        width = max(92, int(screen_w * 0.13))
        height = max(26, int(screen_h * 0.04))
        left = x - width // 2
        top = y - height // 2
        sdl2.SDL_SetRenderDrawBlendMode(Display.renderer.sdlrenderer, sdl2.SDL_BLENDMODE_BLEND)
        sdl2.SDL_SetRenderDrawColor(Display.renderer.sdlrenderer, color[0], color[1], color[2], 255)
        sdl2.SDL_RenderDrawRect(Display.renderer.sdlrenderer, sdl2.SDL_Rect(left, top, width, height))
        sdl2.SDL_RenderDrawRect(Display.renderer.sdlrenderer, sdl2.SDL_Rect(left + 2, top + 2, width - 4, height - 4))
        fill_width = max(0, int((width - 10) * percent / 100))
        if fill_width > 0:
            sdl2.SDL_RenderFillRect(Display.renderer.sdlrenderer, sdl2.SDL_Rect(left + 5, top + 5, fill_width, height - 10))

    @classmethod
    def _draw_battery_segments(cls, percent, x, y, color, screen_w, screen_h, Display):
        segments = 5
        width = max(100, int(screen_w * 0.14))
        height = max(24, int(screen_h * 0.035))
        gap = 4
        segment_w = (width - gap * (segments - 1)) // segments
        left = x - width // 2
        top = y - height // 2
        filled = max(0, min(segments, int(round(percent / 20))))
        sdl2.SDL_SetRenderDrawBlendMode(Display.renderer.sdlrenderer, sdl2.SDL_BLENDMODE_BLEND)
        for index in range(segments):
            alpha = 255 if index < filled else 70
            sdl2.SDL_SetRenderDrawColor(Display.renderer.sdlrenderer, color[0], color[1], color[2], alpha)
            rect = sdl2.SDL_Rect(left + index * (segment_w + gap), top, segment_w, height)
            if index < filled:
                sdl2.SDL_RenderFillRect(Display.renderer.sdlrenderer, rect)
            else:
                sdl2.SDL_RenderDrawRect(Display.renderer.sdlrenderer, rect)

    @classmethod
    def _draw_text(cls, text, x, y, color, font_size, Display, center=True, widget=None):
        font_path = cls._get_widget_font(widget)
        try:
            font = sdl2.sdlttf.TTF_OpenFont(font_path.encode("utf-8"), font_size) if font_path else None
        except Exception:
            font = None

        if font is None:
            return

        try:
            sdl_color = sdl2.SDL_Color(color[0], color[1], color[2], 255)
            surface = sdl2.sdlttf.TTF_RenderUTF8_Blended(font, text.encode("utf-8"), sdl_color)
            if not surface:
                return

            texture = sdl2.SDL_CreateTextureFromSurface(Display.renderer.renderer, surface)
            if not texture:
                sdl2.SDL_FreeSurface(surface)
                return

            w = surface.contents.w
            h = surface.contents.h
            if center:
                draw_x = x - w // 2
            else:
                draw_x = x
            draw_y = y - h // 2

            dst = sdl2.SDL_Rect(draw_x, draw_y, w, h)
            sdl2.SDL_RenderCopy(Display.renderer.renderer, texture, None, dst)
            sdl2.SDL_DestroyTexture(texture)
            sdl2.SDL_FreeSurface(surface)
        except Exception as e:
            PyUiLogger.get_logger().error(f"ScreenSaver text render error: {e}")
        finally:
            sdl2.sdlttf.TTF_CloseFont(font)

    @classmethod
    def _get_widget_font(cls, widget):
        font = widget.get("font") if widget else None
        candidates = []
        if font:
            candidates.append(font)
            candidates.append(os.path.join("/mnt/SDCARD/App/PyUI/fonts", font))
            candidates.append(os.path.join(Theme.get_theme_path(), font))
        candidates.append(Theme.get_font(FontPurpose.LIST))
        for path in candidates:
            if path and os.path.exists(path):
                return path
        return None
