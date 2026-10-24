"""The SDL window/renderer operations PyUI uses, without importing sdl2.ext."""

import ctypes

import sdl2


def _error(action):
    message = (sdl2.SDL_GetError() or b'Unknown SDL error').decode('utf-8', errors='replace')
    return RuntimeError('SDL failed while %s: %s' % (action, message))


def init():
    """Initialize the same video/events subsystems as sdl2.ext.init(controller=False)."""
    if sdl2.SDL_Init(0) != 0:
        raise _error('initializing')
    for subsystem in (sdl2.SDL_INIT_EVENTS, sdl2.SDL_INIT_VIDEO):
        if sdl2.SDL_InitSubSystem(subsystem) != 0:
            raise _error('initializing video/events')


class Window:
    """Own the SDL window used by a device's create_window method."""

    def __init__(self, title, size, flags):
        self.window = None
        self.window = sdl2.SDL_CreateWindow(
            title.encode('utf-8'), sdl2.SDL_WINDOWPOS_UNDEFINED,
            sdl2.SDL_WINDOWPOS_UNDEFINED, size[0], size[1], flags)
        if not self.window:
            raise _error('creating a window')

    def show(self):
        if not self.window:
            raise RuntimeError('Cannot show a closed window')
        sdl2.SDL_ShowWindow(self.window)

    def close(self):
        if self.window:
            sdl2.SDL_DestroyWindow(self.window)
            self.window = None

    def __del__(self):
        self.close()


class Renderer:
    """Own an SDL renderer, retaining the window for its full lifetime."""

    def __init__(self, window, flags):
        self.window = window
        self.renderer = None
        self.renderer = sdl2.SDL_CreateRenderer(window.window, -1, flags)
        if not self.renderer:
            raise _error('creating a renderer')
        sdl2.SDL_ClearError()
        width, height = ctypes.c_int(), ctypes.c_int()
        sdl2.SDL_GetWindowSize(window.window, ctypes.byref(width), ctypes.byref(height))
        sdl2.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 0)
        if sdl2.SDL_RenderSetLogicalSize(self.renderer, width.value, height.value) != 0:
            error = _error('setting renderer size')
            self.destroy()
            raise error

    @property
    def sdlrenderer(self):
        if not self.renderer:
            raise RuntimeError('Cannot use a destroyed renderer')
        return self.renderer

    def present(self):
        sdl2.SDL_RenderPresent(self.sdlrenderer)

    def destroy(self):
        if self.renderer:
            sdl2.SDL_DestroyRenderer(self.renderer)
            self.renderer = None

    def __del__(self):
        self.destroy()
