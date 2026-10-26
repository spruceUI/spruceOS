import ctypes
import os

import sdl2
from sdl2 import sdlimage

from display.display import Display


class CaptureError(RuntimeError):
    pass


def capture_frame(path):
    """Save the frame PyUI last presented to path as a PNG, at the logical resolution.

    PyUI draws into an off-screen canvas and sets it back as the render target after
    presenting, so the current render target holds exactly what is on screen, unscaled.
    """
    if Display.renderer is None:
        raise CaptureError("PyUI's display is not initialised")
    renderer = Display.renderer.sdlrenderer
    width, height = _target_size(renderer)
    pixel_format = sdl2.SDL_PIXELFORMAT_ARGB8888
    surface = sdl2.SDL_CreateRGBSurfaceWithFormat(0, width, height, 32, pixel_format)
    if not surface:
        raise CaptureError(f"SDL_CreateRGBSurfaceWithFormat: {sdl2.SDL_GetError().decode()}")
    try:
        contents = surface.contents
        if sdl2.SDL_RenderReadPixels(renderer, None, pixel_format, contents.pixels, contents.pitch):
            raise CaptureError(f"SDL_RenderReadPixels: {sdl2.SDL_GetError().decode()}")
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        if sdlimage.IMG_SavePNG(surface, os.fsencode(path)):
            raise CaptureError(f"IMG_SavePNG: {sdl2.SDL_GetError().decode()}")
    finally:
        sdl2.SDL_FreeSurface(surface)


def _target_size(renderer):
    width, height = ctypes.c_int(), ctypes.c_int()
    target = sdl2.SDL_GetRenderTarget(renderer)
    if target:
        sdl2.SDL_QueryTexture(target, None, None, ctypes.byref(width), ctypes.byref(height))
    else:
        sdl2.SDL_GetRendererOutputSize(renderer, ctypes.byref(width), ctypes.byref(height))
    return width.value, height.value
