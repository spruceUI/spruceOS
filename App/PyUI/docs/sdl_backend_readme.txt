SDL backend selection
=====================

display/sdl_backend.py is the shared entry point for the SDL operations PyUI
uses: init(), Window(title, size, flags), and Renderer(window, flags).

The implementations are separate modules:
  display/sdl_backend_direct.py  Small base-SDL wrappers; the default.
  display/sdl_backend_ext.py     The original sdl2.ext Window and Renderer.

Only the selected implementation is imported. The default keeps sdl2.ext's
optional network/archive helpers off the startup path.

For a device-specific fallback, override DeviceCommon.get_sdl_backend():

    def get_sdl_backend(self):
        return "ext"

For a quick test, set PYUI_SDL_BACKEND=ext before starting a new UI process.
PYUI_SDL_BACKEND=direct explicitly selects the default. The environment
override takes precedence over the device method. For example, on desktop:

    PYUI_SDL_BACKEND=ext python3 App/PyUI/main-ui/desktop.py

The choice is pinned for the process: windows and renderers always come from
the same implementation, including display reinitialization. Restart the UI
to apply a different choice. The display timing log includes "(direct)" or
"(ext)" so bug reports identify which implementation ran.

Both implementations retain the same resource ownership contract: free
textures, call renderer.destroy(), then window.close(), before SDL_Quit().
