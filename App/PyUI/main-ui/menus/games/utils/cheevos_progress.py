"""Identify the selected ROM, then hand off to Cheevos for that game's progress."""

import json
import os
import shlex
import signal
import subprocess
import tempfile
import time

from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from menus.games.utils.cheevos_cache_manager import CheevosCacheManager
from menus.games.utils.cheevos_identification_cache import (
    IdentificationCache,
    valid_result,
)
from menus.language.language import Language
from utils.py_ui_config import PyUiConfig

APP_DIR = "/mnt/SDCARD/App/Cheevos"
IDENTIFY_MODULE_PATH = "/mnt/SDCARD/App/RAOfflineProxy/app/raofflineproxy/identify_rom.py"
WORK_DIR = "/mnt/SDCARD/Saves/cheevos/cache/identify-work"
IDENTIFY_TIMEOUT = 60


def available():
    """Require the CLI and a Cheevos package advertising the game-ID launch contract."""
    if not PyUiConfig.get_raproxy_cli_cmd() or not os.path.isfile(IDENTIFY_MODULE_PATH):
        return False
    try:
        with open(os.path.join(APP_DIR, "config.json")) as source:
            config = json.load(source)
        return (
            isinstance(config, dict)
            and type(config.get("gameProgress")) is int
            and config["gameProgress"] >= 1
            and os.path.isfile(os.path.join(APP_DIR, "launch.sh"))
        )
    except (OSError, ValueError, TypeError):
        return False


def _stop(process):
    """Stop the helper's shell and Python child without leaving an orphaned lookup."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.communicate(timeout=2)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
    except ProcessLookupError:
        process.communicate()


def identify(path):
    """Trust Spruce's known game first, then saved associations, hashing only unknown paths."""
    result = {"status": "matched", "game_id": CheevosCacheManager.game_id_for_path(path)}
    if valid_result(result):
        return result
    cache = IdentificationCache()
    cached = cache.lookup(path)
    if cached is not None:
        return cached
    result = _identify_with_helper(path)
    cache.remember(path, result)
    return result


def _identify_with_helper(path):
    """Own the helper's scratch so cancellation also cleans up after a forced kill."""
    try:
        os.makedirs(WORK_DIR, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="lookup-", dir=WORK_DIR) as scratch:
            return _run_helper(path, scratch)
    except OSError:
        return {"status": "error", "reason": "unavailable"}


def _run_helper(path, scratch):
    """Keep Spruce responsive while resolving a ROM; B aborts before any handoff."""
    command = PyUiConfig.get_raproxy_cli_cmd()
    try:
        process = subprocess.Popen(
            [command, "identify-rom", "--path", path, "--json"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            start_new_session=True,
            env=dict(os.environ, RAOFFLINEPROXY_HASH_WORK_DIR=scratch),
        )
    except (OSError, TypeError):
        return {"status": "error", "reason": "unavailable"}
    deadline = time.monotonic() + IDENTIFY_TIMEOUT
    try:
        while process.poll() is None:
            Display.display_message(
                Language.label("checkingGameAchievements", "Checking RetroAchievements...")
            )
            Controller.get_input(timeout=0.08)
            if Controller.last_input() == ControllerInput.B:
                return {"status": "cancelled"}
            if time.monotonic() >= deadline:
                return {"status": "error", "reason": "timeout"}
        output, _ = process.communicate()
        # A helper failure must retain its structured reason, even with a nonzero exit.
        result = json.loads(output)
        if not isinstance(result, dict):
            raise ValueError("invalid identification response")
        return result
    except (OSError, ValueError):
        return {"status": "error", "reason": "unavailable"}
    finally:
        if process.poll() is None:
            _stop(process)


def _error_message(result):
    """Translate stable resolver outcomes without exposing backend error strings."""
    if result.get("status") == "no_match":
        return Language.label(
            "noGameAchievementsMatch", "No known RetroAchievements game matches this ROM's hash."
        )
    messages = {
        "auth": (
            "gameAchievementsLogin",
            "Sign in to RetroAchievements in Spruce or RetroArch first.",
        ),
        "offline": ("gameAchievementsOffline", "Connect to Wi-Fi to identify this game."),
        "network": (
            "gameAchievementsNetwork",
            "RetroAchievements is unavailable. Try again later.",
        ),
        "rate_limited": (
            "gameAchievementsRateLimited",
            "RetroAchievements asked to wait. Try again later.",
        ),
        "hash": ("gameAchievementsHash", "Couldn't identify this ROM format or read its contents."),
        "file": ("gameAchievementsFile", "This ROM file is unavailable."),
        "timeout": ("gameAchievementsTimeout", "Game identification timed out. Try again later."),
        "response": (
            "gameAchievementsResponse",
            "RetroAchievements returned an unexpected response.",
        ),
    }
    key, fallback = messages.get(
        result.get("reason"),
        (
            "gameAchievementsUnavailable",
            "Game identification is unavailable. Update RAOfflineProxy and try again.",
        ),
    )
    return Language.label(key, fallback)


def show_progress(rom_info):
    """Launch Cheevos only after the resolver returns a valid RA game ID."""
    result = identify(rom_info.rom_file_path)
    if result.get("status") == "cancelled":
        return
    game_id = result.get("game_id")
    if result.get("status") != "matched" or type(game_id) is not int or game_id <= 0:
        Display.display_message(_error_message(result), duration_ms=3500)
        return
    # The quoted executable uses MiyooTrimCommon.run_app's command-with-arguments path.
    launch = '"' + os.path.join(APP_DIR, "launch.sh") + '" --game-id ' + shlex.quote(str(game_id))
    Display.deinit_display()
    Device.get_device().run_app(APP_DIR, launch)
