import json
import os
import subprocess

from menus.language.language import Language
from utils.cfw_system_config import CfwSystemConfig
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig


def enabled():
    return (PyUiConfig.get_raproxy_cli_cmd() is not None
            and "True" == CfwSystemConfig.get_selected_value(
                "RetroAchievements Settings", "enableOfflineProxy"))


def run(*args, timeout=120):
    cmd = PyUiConfig.get_raproxy_cli_cmd()
    if not cmd:
        return None
    try:
        result = subprocess.run([cmd, *args], capture_output=True, text=True, timeout=timeout)
    except Exception as e:
        PyUiLogger.get_logger().error(f"RAOfflineProxy {args[0]} failed: {e}")
        return None
    if result.returncode != 0:
        PyUiLogger.get_logger().error(
            f"RAOfflineProxy {args[0]} exited {result.returncode}: {result.stderr.strip()[-300:]}")
        return None
    return result.stdout


def run_json(*args, timeout=120):
    out = run(*args, timeout=timeout)
    if out is None:
        return None
    for line in reversed(out.strip().splitlines()):
        try:
            return json.loads(line)
        except ValueError:
            continue
    return None


def rom_key(path):
    parts = [p for p in str(path).replace("\\", "/").split("/") if p]
    return "/" + "/".join(parts[-2:])


_watched = None


def is_watched(path):
    global _watched
    if _watched is None:
        folders = run_json("watched-folders", "--json")
        _watched = {f.get("path") for f in folders or [] if isinstance(f, dict)}
    return os.path.abspath(path) in _watched


def _duration_text(minutes):
    if minutes < 90:
        return f"{minutes} minutes"
    return f"{round(minutes / 60)} hours"


def watch_folder(path, title):
    from display.display import Display
    from utils.user_prompt import UserPrompt

    Display.display_message(Language.label("checkingCheevosFolder", "Checking games..."))
    path = os.path.abspath(path)
    estimate = run_json("estimate-cache", "--path", path, "--json") or {}
    if estimate.get("needs_confirmation"):
        games = estimate.get("cached_now", 0) + estimate.get("newly_queued", 0)
        if not UserPrompt.prompt_yes_no(title, [
                Language.label("cheevosFolderGames", "Up to {games} games to cache.").replace("{games}", str(games)),
                Language.label("cheevosFolderTime", "This happens in the background over about {time}.")
                    .replace("{time}", _duration_text(estimate.get("eta_minutes", 0))),
                Language.label("cheevosFolderOnline", "Caching needs WiFi.")]):
            return False
    if run("watch-folder", "--path", path) is None:
        return False
    is_watched(path)
    _watched.add(path)
    return True


def unwatch_folder(path):
    path = os.path.abspath(path)
    if run("unwatch-folder", "--path", path) is None:
        return False
    is_watched(path)
    _watched.discard(path)
    return True


def toggle_watch(path, title):
    if is_watched(path):
        unwatch_folder(path)
    else:
        watch_folder(path, title)


def run_smart_cache(title):
    from display.display import Display
    from utils.user_prompt import UserPrompt

    Display.display_message(Language.label("checkingCheevosFolder", "Checking games..."))
    status = run_json("smart-cache-status") or {}
    total = status.get("total_candidates", 0)
    if not total:
        return Language.label("noRecentCheevosGames", "No recently played games found")
    if total > 100 and not UserPrompt.prompt_yes_no(title, [
            Language.label("cheevosRecentGames", "{games} recently played games.").replace("{games}", str(total)),
            Language.label("cheevosRecentQueue", "The first 100 are cached now, the rest over time."),
            Language.label("cheevosFolderOnline", "Caching needs WiFi.")]):
        return None

    cmd = PyUiConfig.get_raproxy_cli_cmd()
    result = {}
    last_line = "Failed"
    try:
        with subprocess.Popen([cmd, "run-smart-cache"], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True) as proc:
            for line in proc.stdout:
                try:
                    event = json.loads(line)
                except ValueError:
                    if line.strip():
                        last_line = line.strip()
                    continue
                if event.get("type") == "progress":
                    Display.display_message(
                        Language.label("cachingCheevosProgress", "Caching {current} of {total}...")
                            .replace("{current}", str(event.get("scanned", 0)))
                            .replace("{total}", str(event.get("total", total))))
                elif event.get("type") == "result":
                    result = event
    except Exception as e:
        PyUiLogger.get_logger().error(f"RAOfflineProxy run-smart-cache failed: {e}")
        return "Failed"

    if not result:
        return last_line
    message = Language.label("cachedCheevosCount", "Cached {cached}").replace("{cached}", str(result.get("cached", 0)))
    if result.get("queued"):
        message += ", " + Language.label("queuedCheevosCount", "{queued} queued").replace("{queued}", str(result["queued"]))
    return message
