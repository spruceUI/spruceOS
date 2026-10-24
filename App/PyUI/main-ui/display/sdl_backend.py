"""Select one SDL implementation for the UI process, keeping window/renderer APIs shared."""

import os

_backend = None
_backend_name = None


def _get_backend():
    global _backend, _backend_name
    if _backend is None:
        name = os.environ.get('PYUI_SDL_BACKEND')
        if not name:
            from devices.device import Device
            device = Device.get_device()
            if device is None:
                raise RuntimeError('Initialize a device before selecting the SDL backend')
            name = device.get_sdl_backend()
        if name == 'direct':
            from display import sdl_backend_direct as implementation
        elif name == 'ext':
            from display import sdl_backend_ext as implementation
        else:
            raise ValueError('Unknown SDL backend %r; expected direct or ext' % name)
        _backend, _backend_name = implementation, name
    return _backend


def get_backend_name():
    """The selected implementation, fixed for this UI process."""
    _get_backend()
    return _backend_name


def init():
    return _get_backend().init()


def Window(title, size, flags):
    return _get_backend().Window(title, size, flags=flags)


def Renderer(window, flags):
    return _get_backend().Renderer(window, flags=flags)
