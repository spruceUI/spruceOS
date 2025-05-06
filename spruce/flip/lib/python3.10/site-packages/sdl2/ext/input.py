from ctypes import c_int, byref
from ..stdinc import SDL_TRUE
from ..keyboard import (
    SDL_GetKeyFromName, SDL_GetKeyName, SDL_StartTextInput, SDL_StopTextInput,
    SDL_IsTextInputActive, SDL_GetKeyboardState, SDL_GetScancodeFromName,
)
from ..scancode import SDL_SCANCODE_UNKNOWN, SDL_NUM_SCANCODES
from ..keycode import KMOD_ALT, KMOD_CTRL, KMOD_GUI, KMOD_SHIFT
from ..mouse import (
    SDL_BUTTON_LEFT, SDL_BUTTON_RIGHT, SDL_BUTTON_MIDDLE,
    SDL_BUTTON_X1, SDL_BUTTON_X2,
)
from ..events import (
    SDL_KEYDOWN, SDL_KEYUP, SDL_MOUSEBUTTONDOWN, SDL_MOUSEBUTTONUP,
    SDL_TEXTINPUT, SDL_PumpEvents,
)

from .compat import _is_text, byteify, isiterable

__all__ = [
    "key_pressed", "get_key_state", "mouse_clicked", "get_clicks", "get_text_input",
    "start_text_input", "stop_text_input", "text_input_enabled",  
]


KEYMOD_MAP = {
    # main mappings
    'ctrl': KMOD_CTRL,
    'alt': KMOD_ALT,
    'gui': KMOD_GUI,
    'shift': KMOD_SHIFT,
    # additional aliases
    'control': KMOD_CTRL,
    'option': KMOD_ALT,
    'command': KMOD_GUI,
    'super': KMOD_GUI,
}

MOUSE_BUTTON_MAP = {
    'left': SDL_BUTTON_LEFT,
    'right': SDL_BUTTON_RIGHT,
    'middle': SDL_BUTTON_MIDDLE,
    'x1': SDL_BUTTON_X1,
    'x2': SDL_BUTTON_X2,
}



def _parse_keycode(key):

    keycode = 0
    if isinstance(key, int):
        if SDL_GetKeyName(key) == b"":
            raise ValueError("'{0}' is not a valid SDL_Keycode".format(key))
        keycode = key

    elif _is_text(key):
        keycode = SDL_GetKeyFromName(byteify(key))
        if keycode == 0:
            raise ValueError("'{0}' is not a valid SDL key name".format(key))
        
    else:
        e = "'key' must be a string or SDL_Keycode (got {0})"
        raise TypeError(e.format(str(type(key))))
    
    return keycode


def _mod_to_masks(mod):

    if not isiterable(mod):
        mod = [mod]
    
    masks = []
    for m in mod:
        # If mod is already an int, assume it's a valid bitmask
        if isinstance(m, int):
            masks.append(m)

        # If mod is a string, validate and convert it to a bitmask
        elif _is_text(m):
            m = m.lower()
            if not m in KEYMOD_MAP.keys():
                e = "'{0}' is not a valid modifer key name"
                raise ValueError(e.format(m))
            masks.append(KEYMOD_MAP[m])

        else:
            e = "'mod' must be a list of strings or SDL bitmasks (got {0})"
            raise TypeError(e.format(str(type(m))))
    
    return masks


def _get_sdl_mouse_button(button):
    
    # Check if valid SDL_BUTTON constant
    if isinstance(button, int):
        if not button in MOUSE_BUTTON_MAP.values():
            e = "'{0}' does not correspond to a valid SDL mouse button"
            raise ValueError(e.format(button))
    
    # Check if valid mouse button name
    elif _is_text(button):
        button = button.lower()
        if not button in MOUSE_BUTTON_MAP.keys():
            e = "'{0}' is not a valid mouse button name"
            raise ValueError(e.format(button))
        button = MOUSE_BUTTON_MAP[button]

    else:
        e = "'button' must be a string or SDL_BUTTON constant (got {0})"
        raise TypeError(e.format(str(type(button))))
    
    return button



def key_pressed(events, key=None, mod=None, released=False):
    """Checks for key press events in a given event queue.
    
    By default, this function will return True if any key has been pressed.
    However, you can also check a specific key by providing its name (e.g.
    'up') or SDL keycode (e.g. ``sdl2.SDLK_up``) to the 'key' argument.

    This function is meant to be used with :func:`~sdl2.ext.get_events`::

        response = None
        while not response:
            q = get_events() # Fetch latest SDL input events
            if key_pressed(q, 'z'):
                response = 'left'
            elif key_pressed(q, '/'):
                response = 'right'

    Additionally, you can check if the key has been pressed while holding one
    or more modifier keys (e.g. control + q to quit the program) by providing
    the name(s) (e.g. 'ctrl') or SDL bitmask(s) (e.g. ``sdl2.KMOD_LCTRL``)
    of the modifiers to the 'mod' argument::

        q = get_events()
        if key_pressed(q, 'q', mod='ctrl'):
            exit_app()
        elif key_pressed(q, 'd', mod=['ctrl', 'shift']):
            debug_mode = True

    Valid modifier names include 'ctrl' and 'control' for the Control keys,
    'alt' and 'option' for the Alt keys, 'gui', 'command', and 'super' for the
    Command/Win/Super keys, and 'shift' for the shift keys. A full list of SDL
    modifier bitmasks can be found here: https://wiki.libsdl.org/SDL2/SDL_Keymod
    
    For a comprehensive list of valid key names, see the 'Name' column of the
    following table: https://wiki.libsdl.org/SDL2/SDL_Scancode

    For a comprehensive list of valid SDL keycodes, consult the following table:
    https://wiki.libsdl.org/SDL_Keycode

    Args:
        events (list of :obj:`sdl2.SDL_Event`): A list of SDL events to check
            for matching key presses (or releases).
        key (str or :obj:`sdl2.SDL_Keycode`, optional): The name or SDL keycode
            of the key to check. If ``None``, will return True on any keypress.
            Defaults to ``None``.
        mod (str or list, optional): The key modifiers (if any) to require for
            the key press (e.g. 'ctrl' for Control-Q). Has no effect if ``key``
            is not specified. Defaults to ``None``.
        released (bool, optional): If True, will check for key release
            events instead of key presses. Defaults to False.

    Returns:
        bool: True if key has been pressed, otherwise False.

    """
    # If key specified, validate and coerce to SDL_Keycode
    keycode = None
    if key:
        keycode = _parse_keycode(key)
        
    # If modifier key(s) specified, validate and coerce to list of bitmasks
    if mod:
        mod = _mod_to_masks(mod)
        
    # Ensure 'events' is iterable
    if not isiterable(events):
        events = [events]

    # Check for any key events matching the criteria in the given event queue
    pressed = False
    for e in events:
        if e.type == (SDL_KEYUP if released else SDL_KEYDOWN):
            if not keycode:
                pressed = True
                break
            elif e.key.keysym.sym == keycode:
                if not mod or all([e.key.keysym.mod & m for m in mod]):
                    pressed = True
                    break

    return pressed


def get_key_state(key):
    """Checks the current state (pressed or released) of a given keyboard key.

    Unlike :func:`key_pressed`, which checks an SDL event queue for key down
    and key up events, this function checks the current state of a given key
    directly. This can be helpful in certain situations, such as ignoring
    repeated keydown events from a held key::

       key_released = False
       while True:
           q = pump(True)
           if not key_released:
               # Ignore repeated keydown events from held down space bar by
               # requiring key be 'up' on at least one loop before a response
               # can be registered
               if get_key_state('space') == 0:
                   key_released = True
           else:
               if key_pressed('space', queue=q):
                   break

    Args:
        key (int or str): The name (or SDL scancode) of the key to check.

    Returns:
        int: 1 if the key is currently pressed, otherwise 0.

    """
    # If key given as string, get the corresponding scancode
    if _is_text(key):
        scancode = SDL_GetScancodeFromName(byteify(key))
        if scancode == SDL_SCANCODE_UNKNOWN:
            e = "'{0}' is not a valid name for an SDL scancode."
            raise ValueError(e.format(key))
    else:
        if key <= 0 or key >= SDL_NUM_SCANCODES:
            e = "'{0}' is not a valid SDL scancode constant."
            raise ValueError(e.format(key))
        scancode = key

    # Check for and return the current key state
    SDL_PumpEvents()
    numkeys = c_int(0)
    keys = SDL_GetKeyboardState(byref(numkeys))
    return keys[scancode]


def mouse_clicked(events, button=None, released=False):
    """Checks for any mouse clicks in a given event queue.

    This function is meant to be used with :func:`~sdl2.ext.get_events`::

        response = None
        while not response:
            q = get_events() # Fetch latest SDL input events
            if mouse_clicked(q, 'left'):
                response = 'left'
            elif mouse_clicked(q, 'right'):
                response = 'right'

    By default, this function checks for clicks from any button. However, you
    can also check for clicks from a specific button by specifying one of the
    following strings or SDL constants for the ``button`` argument:

    ===================== =============
    SDL Constant          String
    ===================== =============
    ``SDL_BUTTON_LEFT``   ``'left'``
    ``SDL_BUTTON_RIGHT``  ``'right'``
    ``SDL_BUTTON_MIDDLE`` ``'middle'``
    ``SDL_BUTTON_X1``     ``'x1'``
    ``SDL_BUTTON_X2``     ``'x2'``
    ===================== =============

    Args:
        events (list of :obj:`sdl2.SDL_Event`): A list of SDL events to check
            for mouse click events.
        button (str or int, optional): The name or SDL constant of the mouse
            button to listen for. If ``None``, all mouse buttons will . Defaults to ``None``.
        released (bool, optional): If True, will check the queue for mouse
            button release events instead of mouse button down events. Defaults
            to False.

    Returns:
        bool: True if the mouse has been clicked, otherwise False.

    """
    # If button specified, validate and coerce to SDL_BUTTON constant
    if button:
        button = _get_sdl_mouse_button(button)

    # Ensure 'events' is iterable
    if not isiterable(events):
        events = [events]

    # Check for any click events matching the criteria in the given event queue
    clicked = False
    for e in events:
        if e.type == (SDL_MOUSEBUTTONUP if released else SDL_MOUSEBUTTONDOWN):
            if not button or e.button.button == button:
                clicked = True
                break

    return clicked


def get_clicks(events, button=None, released=False):
    """Returns the (x, y) coordinates of the mouse clicks in an event queue.

    By default, this function returns clicks from any button. However, you can
    also return clicks from a specific button only by specifying a string or
    SDL button constant (see :func:`mouse_clicked` for details).

    Args:
        events (list of :obj:`sdl2.SDL_Event`): A list of SDL events to check
            for mouse click events.
        button (str or int, optional): The name or SDL constant of the mouse
            button to listen for. If ``None``, will return clicks from any mouse
            button. Defaults to ``None``.
        released (bool, optional): If True, will return the coordinates for
            mouse button release events instead of mouse button click events.
            Defaults to False.

    Returns:
        list: A list of the (x, y) coordinates for each matching click event
        in the queue.
    
    """
    # If button specified, validate and coerce to SDL_BUTTON constant
    if button:
        button = _get_sdl_mouse_button(button)

    # Ensure 'events' is iterable
    if not isiterable(events):
        events = [events]

    # Gather and return any matching mouse clicks in the given queue
    clicks = []
    for e in events:
        if e.type == (SDL_MOUSEBUTTONUP if released else SDL_MOUSEBUTTONDOWN):
            if not button or e.button.button == button:
                clicks.append((e.button.x, e.button.y))

    return clicks


def start_text_input():
    """Enables SDL unicode text input events.

    """
    SDL_StartTextInput()


def stop_text_input():
    """Disables SDL unicode text input events.

    """
    SDL_StopTextInput()


def text_input_enabled():
    """Checks whether SDL text input events are currently enabled.

    Returns:
        bool: True if text input events are enabled, otherwise False.

    """
    return SDL_IsTextInputActive() == SDL_TRUE


def get_text_input(events):
    """Returns the text input events from a queue as a unicode string.

    Note that SDL text input events need to be enabled for this function to
    work. This can be toggled with :func:`start_text_input` /
    :func:`stop_text_input` and queried with :func:`text_input_enabled`::

        start_text_input()

        response = u""
        while True:
            q = get_events()
            if key_pressed(q, 'return'):
                break
            response += get_text_input(q)
            draw_text(response)

        stop_text_input()

    If there are no text input events in the given event queue, an empty unicode
    string will be returned.

    Args:
        events (list of :obj:`sdl2.SDL_Event`): A list of SDL events to check
            for unicode text input (``SDL_TEXTINPUT``) events.

    Returns:
        str: A UTF8-encoded unicode string containing all text input from the
        queue.

    """
    # Make sure text input events are enabled
    if not text_input_enabled():
        e = "Text input events must be enabled before using get_text()"
        raise RuntimeError(e)

    # Ensure 'events' is iterable
    if not isiterable(events):
        events = [events]

    # Check for any key events matching the criteria in the given event queue
    text = u""
    for e in events:
        if e.type == SDL_TEXTINPUT:
            text += e.text.text.decode('utf-8')

    return text
