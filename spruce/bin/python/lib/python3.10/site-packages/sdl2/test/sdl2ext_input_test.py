# -*- coding: utf-8 -*-
import pytest
from ..scancode import SDL_SCANCODE_SPACE, SDL_SCANCODE_A
from ..keycode import SDLK_a, KMOD_LSHIFT, KMOD_RCTRL
from ..mouse import SDL_BUTTON_LEFT
from ..events import (
    SDL_Event, SDL_TEXTINPUT, SDL_MOUSEBUTTONUP, SDL_MOUSEBUTTONDOWN,
    SDL_KEYDOWN, SDL_KEYUP,
)
from sdl2 import ext as sdl2ext
from sdl2.ext.input import MOUSE_BUTTON_MAP, _parse_keycode


@pytest.fixture(scope="module")
def with_sdl():
    sdl2ext.init()
    yield
    sdl2ext.quit()

@pytest.fixture(scope="module")
def with_ext_window(with_sdl):
    win = sdl2ext.Window("Test", (100, 100))
    win.show()
    yield win
    win.close()

def textinput(char):
    # Generate a simulated text input event
    e = SDL_Event()
    e.type = SDL_TEXTINPUT
    e.text.type = SDL_TEXTINPUT
    e.text.text = char.encode('utf-8')
    return e

def key(k, mod = 0, released = False):
    e = SDL_Event()
    e.type = SDL_KEYUP if released else SDL_KEYDOWN 
    e.key.type = SDL_KEYUP if released else SDL_KEYDOWN 
    e.key.keysym.sym = _parse_keycode(k)
    e.key.keysym.mod = mod
    return e

def click(button = 'right', loc = (0, 0), release = False):
    # Generate a simulated mouse click event
    etype = SDL_MOUSEBUTTONUP if release else SDL_MOUSEBUTTONDOWN
    e = SDL_Event()
    e.type = etype
    e.button.type = etype
    e.button.x, e.button.y = loc
    e.button.button = MOUSE_BUTTON_MAP[button]
    return e


def test_start_stop_text_input(with_ext_window):
    # Try toggling text input
    sdl2ext.stop_text_input()
    assert not sdl2ext.text_input_enabled()
    sdl2ext.start_text_input()
    assert sdl2ext.text_input_enabled()
    sdl2ext.stop_text_input()
    assert not sdl2ext.text_input_enabled()


def test_get_text_input(with_ext_window):
    q = [
        textinput(u"h"),
        textinput(u"é"),
        textinput(u"l"),
        textinput(u"l"),
        textinput(u"ø"),
    ]
    # Enable text input
    sdl2ext.start_text_input()
    assert sdl2ext.text_input_enabled()
    # Test with empty queue
    assert sdl2ext.get_text_input([]) == u""
    # Test with simulated input
    assert sdl2ext.get_text_input(q) == u"héllø"
    # Test exception when text input disabled
    sdl2ext.stop_text_input()
    assert not sdl2ext.text_input_enabled()
    with pytest.raises(RuntimeError):
        sdl2ext.get_text_input(q)


def test_key_pressed():
    # Test with empty queue
    assert sdl2ext.key_pressed([]) == False
    # Test with simulated key events
    q = [key('a'), key('b'), key('c', released=True)]
    assert sdl2ext.key_pressed(q) == True
    assert sdl2ext.key_pressed(q, 'a') == True
    assert sdl2ext.key_pressed(q, SDLK_a) == True
    assert sdl2ext.key_pressed(q, 'b') == True
    assert sdl2ext.key_pressed(q, 'z') == False
    assert sdl2ext.key_pressed(q, 'c') == False
    assert sdl2ext.key_pressed(q, 'b', released=True) == False
    assert sdl2ext.key_pressed(q, 'c', released=True) == True
    # Test with modifier keys
    q = [key('a'), key('b', mod=KMOD_LSHIFT), key('c', mod=(KMOD_LSHIFT|KMOD_RCTRL))]
    assert sdl2ext.key_pressed(q, 'a', mod='shift') == False
    assert sdl2ext.key_pressed(q, 'b', mod='shift') == True
    assert sdl2ext.key_pressed(q, 'c', mod='shift') == True
    assert sdl2ext.key_pressed(q, 'b', mod=KMOD_LSHIFT) == True
    assert sdl2ext.key_pressed(q, 'b', mod=['ctrl', 'shift']) == False
    assert sdl2ext.key_pressed(q, 'c', mod=['ctrl', 'shift']) == True
    assert sdl2ext.key_pressed(q, 'c', mod=[KMOD_LSHIFT, KMOD_RCTRL]) == True
    # Test with single event
    assert sdl2ext.key_pressed(q[0], 'a') == True
    # Test exception on bad buttons
    with pytest.raises(ValueError):
        sdl2ext.key_pressed(q, 'nope')
    with pytest.raises(ValueError):
        sdl2ext.key_pressed(q, key=-100)


def test_get_key_state():
    # NOTE: Can't fake key status for tests, so just test API
    assert sdl2ext.get_key_state('space') in (0, 1)
    assert sdl2ext.get_key_state('a') in (0, 1)
    assert sdl2ext.get_key_state(SDL_SCANCODE_SPACE) in (0, 1)
    assert sdl2ext.get_key_state(SDL_SCANCODE_A) in (0, 1)
    # Test exception on bad key names/scancodes
    with pytest.raises(ValueError):
        sdl2ext.get_key_state('nope')
    with pytest.raises(ValueError):
        sdl2ext.get_key_state(0)
    with pytest.raises(ValueError):
        sdl2ext.get_key_state(1000)


def test_mouse_clicked():
    # Test with empty queue
    assert sdl2ext.mouse_clicked([]) == False
    # Test with simulated clicks
    q = [
        click('left'),
        click('middle'),
        click('right', release=True),
    ]
    assert sdl2ext.mouse_clicked(q) == True
    assert sdl2ext.mouse_clicked(q, 'left') == True
    assert sdl2ext.mouse_clicked(q, 'middle') == True
    assert sdl2ext.mouse_clicked(q, 'right') == False
    assert sdl2ext.mouse_clicked(q, 'left', released=True) == False
    assert sdl2ext.mouse_clicked(q, 'right', released=True) == True
    # Test with single event
    assert sdl2ext.mouse_clicked(q[0], 'left') == True
    # Test exception on bad buttons
    with pytest.raises(ValueError):
        sdl2ext.mouse_clicked(q, 'upper-middle')
    with pytest.raises(ValueError):
        sdl2ext.mouse_clicked(q, button=100)


def test_get_clicks():
    # Test with empty queue
    assert sdl2ext.get_clicks([]) == []
    # Test with simulated clicks
    q = [
        click('left', loc=(10, 20)),
        click('left', loc=(30, 20)),
        click('middle', loc=(100, 100)),
        click('right', loc=(45, 432), release=True),
    ]
    assert sdl2ext.get_clicks(q) == [(10, 20), (30, 20), (100, 100)]
    assert sdl2ext.get_clicks(q, 'left') == [(10, 20), (30, 20)]
    assert sdl2ext.get_clicks(q, SDL_BUTTON_LEFT) == [(10, 20), (30, 20)]
    assert sdl2ext.get_clicks(q, 'middle') == [(100, 100)]
    assert sdl2ext.get_clicks(q, 'right') == []
    assert sdl2ext.get_clicks(q, 'left', released=True) == []
    assert sdl2ext.get_clicks(q, 'right', released=True) == [(45, 432)]
    # Test with single event
    assert sdl2ext.get_clicks(q[0], 'left') == [(10, 20)]
    # Test exception on bad buttons
    with pytest.raises(ValueError):
        sdl2ext.get_clicks(q, 'upper-middle')
    with pytest.raises(ValueError):
        sdl2ext.get_clicks(q, button=100)
