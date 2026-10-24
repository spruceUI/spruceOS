"""The original PySDL2 extension backend, loaded only when a device selects it."""

from sdl2 import ext

Window = ext.Window
Renderer = ext.Renderer


def init():
    """Keep the same video/events-only initialization as the direct backend."""
    return ext.init(controller=False)
