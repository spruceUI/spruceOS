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
from menus.language.language import Language

APP_DIR = "/mnt/SDCARD/App/Cheevos"
LAUNCH_SCRIPT = os.path.join(APP_DIR, "launch.sh")
# Cheevos's headless helper: saved path matches, then RAOfflineProxy's hasher and RA.
IDENTIFY_SCRIPT = os.path.join(APP_DIR, "identify-rom.sh")
# config.json "gameProgress": 1 opens --game-id N; 2 also ships identify-rom.sh.
IDENTIFY_CONTRACT = 2
WORK_DIR = "/mnt/SDCARD/Saves/cheevos/cache/identify-work"
IDENTIFY_TIMEOUT = 60


def available():
    """Require a Cheevos package that ships the identification helper and game-ID launches."""
    try:
        with open(os.path.join(APP_DIR, "config.json")) as source:
            config = json.load(source)
        return (
            isinstance(config, dict)
            and type(config.get("gameProgress")) is int
            and config["gameProgress"] >= IDENTIFY_CONTRACT
            and os.path.isfile(LAUNCH_SCRIPT)
            and os.path.isfile(IDENTIFY_SCRIPT)
        )
    except (OSError, ValueError, TypeError):
        return False


def _stop(process):
    """Stop the helper's whole process group without leaving an orphaned lookup."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.communicate(timeout=2)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
    except ProcessLookupError:
        process.communicate()


def identify(path):
    """Trust Spruce's loaded game mapping first; Cheevos's helper handles every other path."""
    game_id = CheevosCacheManager.game_id_for_path(path)
    if type(game_id) is int and game_id > 0:
        return {"status": "matched", "game_id": game_id}
    return _identify_with_helper(path)


def _identify_with_helper(path):
    """Own the helper's scratch so cancellation also cleans up after a forced kill."""
    try:
        os.makedirs(WORK_DIR, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="lookup-", dir=WORK_DIR) as scratch:
            return _run_helper(path, scratch)
    except OSError:
        return {"status": "error", "reason": "unavailable"}


def _parse_result(output):
    """Accept only the helper's documented results; anything else is a failed lookup."""
    try:
        result = json.loads(output)
    except (TypeError, ValueError):
        result = None
    if not isinstance(result, dict):
        return {"status": "error", "reason": "unavailable"}
    status, game_id = result.get("status"), result.get("game_id")
    if status == "matched" and type(game_id) is int and game_id > 0:
        return {"status": "matched", "game_id": game_id}
    if status == "no_match":
        return {"status": "no_match"}
    if status == "error" and isinstance(result.get("reason"), str):
        return {"status": "error", "reason": result["reason"]}
    return {"status": "error", "reason": "unavailable"}


def _run_helper(path, scratch):
    """Keep Spruce responsive while resolving a ROM; B aborts before any handoff."""
    try:
        process = subprocess.Popen(
            [IDENTIFY_SCRIPT, "--path", os.path.abspath(path), "--work-dir", scratch, "--json"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            start_new_session=True,
        )
    except OSError:
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
        # The helper's JSON keeps its reason whatever its exit status; a crash has none.
        return _parse_result(output)
    except OSError:
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
        "dependency": (
            "gameAchievementsDependency",
            "Game identification needs a compatible RAOfflineProxy.",
        ),
    }
    key, fallback = messages.get(
        result.get("reason"),
        (
            "gameAchievementsUnavailable",
            "Game identification is unavailable. Update Cheevos and try again.",
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
    launch = '"' + LAUNCH_SCRIPT + '" --game-id ' + shlex.quote(str(game_id))
    Display.deinit_display()
    Device.get_device().run_app(APP_DIR, launch)
