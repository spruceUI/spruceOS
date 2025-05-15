# pytest configuration file
import os
import sys
import gc
import pytest
import sdl2
from sdl2 import ext as sdl2ext

# A flag to skip annoying audiovisual tests (e.g. window minimize).
# Defaults to True unless an environment variable is explicitly set.
SKIP_ANNOYING = os.getenv("PYSDL2_ALL_TESTS", "0") == "0"

# Set a global constant identifying the current video driver
SDL_VIDEODRIVER = "dummy"
try:
    sdl2.SDL_Init(sdl2.SDL_INIT_VIDEO)
    SDL_VIDEODRIVER = sdl2.SDL_GetCurrentVideoDriver()
    sdl2.SDL_Quit()
    if sys.version_info[0] >= 3:
        SDL_VIDEODRIVER = SDL_VIDEODRIVER.decode('utf-8')
except:
    pass


@pytest.fixture(scope="module")
def with_sdl():
    sdl2.SDL_ClearError()
    ret = sdl2.SDL_Init(sdl2.SDL_INIT_VIDEO | sdl2.SDL_INIT_TIMER)
    assert ret == 0, sdl2.SDL_GetError().decode('utf-8', 'replace')
    yield
    sdl2.SDL_Quit()

@pytest.fixture(autouse=True)
def sdl_cleanup():
    sdl2.SDL_ClearError()
    yield
    sdl2.SDL_ClearError()
    gc.collect()


def _check_error_msg():
    # Convenience function for retrieving the current SDL error as a str
    e = sdl2.SDL_GetError()
    if sys.version_info[0] >= 3:
        e = e.decode('utf-8', 'replace')
    return e
