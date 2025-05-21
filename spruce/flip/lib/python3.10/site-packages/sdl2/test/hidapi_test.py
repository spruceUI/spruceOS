import sys
import pytest
import sdl2
from sdl2.stdinc import SDL_TRUE, SDL_FALSE
from sdl2.error import SDL_GetError, SDL_ClearError
from .conftest import _check_error_msg

# Make sure hidapi subsystem is available and works before running tests
skipmsg = 'HIDAPI requires SDL 2.0.18 or newer'
pytestmark = pytest.mark.skipif(sdl2.dll.version < 2018, reason=skipmsg)


@pytest.fixture
def hidapi_setup():
    SDL_ClearError()
    ret = sdl2.SDL_hid_init()
    assert ret == 0
    yield ret  # Run the test
    ret = sdl2.SDL_hid_exit()
    assert ret == 0


def test_SDL_hid_init_exit():
    SDL_ClearError()
    # Initialize the library
    ret = sdl2.SDL_hid_init()
    assert ret == 0, _check_error_msg()
    # Exit the library
    ret = sdl2.SDL_hid_exit()
    assert ret == 0, _check_error_msg()


def test_SDL_hid_device_change_count(hidapi_setup):
    # Check for HID device changes
    ret = sdl2.SDL_hid_device_change_count()
    assert ret >= 0


def test_SDL_hid_enumerate(hidapi_setup):
    devices = sdl2.SDL_hid_enumerate(0, 0)
    # Cannot check the error indicator here: a non-error empty list is
    # indistinguishable from an error, and it is not guaranteed that the
    # error indicator will not be set as a side-effect of a successful load
    if devices != None:
        sdl2.SDL_hid_free_enumeration(devices)


@pytest.mark.skip("not implemented")
def test_SDL_hid_open_close():
    # SDL_hid_open & SDL_hid_close
    pass

@pytest.mark.skip("not implemented")
def test_SDL_hid_open_path():
    pass

@pytest.mark.skip("not implemented")
def test_SDL_hid_write():
    pass

@pytest.mark.skip("not implemented")
def test_SDL_hid_read_timeout():
    pass

@pytest.mark.skip("not implemented")
def test_SDL_hid_read():
    pass

@pytest.mark.skip("not implemented")
def test_SDL_hid_set_nonblocking():
    pass

@pytest.mark.skip("not implemented")
def test_SDL_hid_send_feature_report():
    pass

@pytest.mark.skip("not implemented")
def test_SDL_hid_get_feature_report():
    pass

@pytest.mark.skip("not implemented")
def test_SDL_hid_get_info_strings():
    # SDL_hid_get_manufacturer_string & SDL_hid_get_product_string &
    # SDL_hid_get_serial_number_string & SDL_hid_get_indexed_string
    pass

@pytest.mark.skip("not implemented")
def test_SDL_hid_ble_scan():
    pass
