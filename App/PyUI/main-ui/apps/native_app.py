"""Run an app inside PyUI's own process, as the Activity Tracker runs, then unload it.

An app opts in with "pyuiEntry": "<module>:<function>" in its config.json, in place of a
"launch" script. PyUI then imports the module from the app's folder and calls the function from
its menu, with the display, theme and controller already up, instead of exiting so
principal.sh can run a script: the app opens at once, and PyUI needs no restart when it closes.

The app must leave PyUI as it found it: none of its threads running and none of its hooks in
PyUI's objects. PyUI then drops every module it imported from the app's folder, so nothing of
the app stays alive. Python's allocators keep part of the freed memory for reuse (6-7 MB
after Cheevos on a Miyoo Mini Plus): the next session reuses it, so PyUI doesn't grow from one
session to the next, and PyUI's restart before every game gives it back.
"""

import ctypes
import gc
import importlib
import linecache
import logging
import os
import re
import sys

from controller.controller import Controller
from display.display import Display
from menus.language.language import Language
from utils.logger import PyUiLogger


def run(folder, entry, **kwargs):
    """Call the app's entry point with kwargs (e.g. game_id) and return when it closes."""
    folder = os.path.abspath(folder)
    module_name, _, function_name = entry.partition(":")
    loaded_before = set(sys.modules)
    # Appended, not inserted: PyUI must stay first (Language finds lang/ from sys.path[0]).
    sys.path.append(folder)
    # The app gets the texture memory the menus were using; they draw theirs again after.
    Display.clear_cache(include_fonts=False)
    try:
        function = getattr(importlib.import_module(module_name), function_name)
        function(**kwargs)
    except Exception:
        PyUiLogger.get_logger().exception(f"App {entry} in {folder} failed")
        Display.display_message(Language.label("appFailed", "The app stopped after an error."), 3000)
    finally:
        function = None
        if folder in sys.path:
            sys.path.remove(folder)
        _unload(folder, loaded_before)
        Display.clear_cache(include_fonts=False)
        Controller.clear_input_queue()


def _unload(folder, loaded_before):
    """Drop what was imported from the app's folder, then give the freed memory back."""
    prefix = folder + os.sep
    dropped = [
        name for name in set(sys.modules) - loaded_before
        if _comes_from(sys.modules[name], prefix)
    ]
    for name in dropped:
        del sys.modules[name]
    packages = {name.split(".")[0] for name in dropped}
    loggers = logging.Logger.manager.loggerDict
    for name in [name for name in loggers if name.split(".")[0] in packages]:
        del loggers[name]
    for path in [path for path in sys.path_importer_cache if path == folder or path.startswith(prefix)]:
        del sys.path_importer_cache[path]
    for path in [path for path in linecache.cache if path.startswith(prefix)]:
        del linecache.cache[path]
    re.purge()
    gc.collect()
    _trim_heap()
    PyUiLogger.get_logger().info(f"Unloaded {len(dropped)} modules from {folder}")


def _comes_from(module, prefix):
    """Whether a module (or package) was loaded from under prefix."""
    paths = [getattr(module, "__file__", None)] + list(getattr(module, "__path__", None) or [])
    return any(isinstance(path, str) and path.startswith(prefix) for path in paths)


def _trim_heap():
    """Return free heap pages to the system: glibc keeps them for the process otherwise."""
    try:
        ctypes.CDLL(None).malloc_trim(0)
    except (OSError, AttributeError):
        pass  # not glibc
