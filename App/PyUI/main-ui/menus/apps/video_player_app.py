import json
import os
import re
import time

from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.on_screen_keyboard import OnScreenKeyboard
from display.display import Display
from menus.language.language import Language
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType

VIDEO_EXTENSIONS = {
    ".mp4", ".mkv", ".avi", ".mov", ".flv", ".ts", ".webm",
    ".m4v", ".wmv", ".mpeg", ".mpg", ".3gp",
}
MEDIA_LAUNCH = "/mnt/SDCARD/Emu/MEDIA/../../spruce/scripts/emu/standard_launch.sh"
VIDEO_CACHE = "/mnt/SDCARD/Saves/spruce/video-index.json"


class VideoPlayerApp:
    def _video_root(self):
        return PyUiConfig.get_video_root_path()

    def run(self, _input=None):
        video_root = self._video_root()
        os.makedirs(video_root, exist_ok=True)
        Controller.clear_input_queue()
        time.sleep(0.2)
        options = [
            GridOrListEntry(
                primary_text=Language.get("browseVideos", "Browse videos"),
                description=Language.get("openMediaFolder", "Open Roms/MEDIA"),
                value=self._browse_root,
            ),
            GridOrListEntry(
                primary_text=Language.get("searchVideos", "Search videos"),
                description=Language.get("findVideosByName", "Find videos by name"),
                value=self._search_videos,
            ),
            GridOrListEntry(
                primary_text=Language.get("refreshVideoIndex", "Refresh video index"),
                description=Language.get("refreshVideoIndexDesc", "Rebuild cached video search list"),
                value=self._refresh_index,
            ),
            GridOrListEntry(
                primary_text=Language.get("videoControls", "Controls"),
                description=Language.get("videoControlsDesc", "Playback button guide"),
                value=self._show_controls,
            ),
        ]
        selected = Selection(None, None, 0)
        view = ViewCreator.create_view(
            view_type=ViewType.ICON_AND_DESC,
            top_bar_text=Language.get("videoPlayer", "Video Player"),
            options=options,
            selected_index=selected.get_index(),
        )
        while True:
            picked = view.get_selection([ControllerInput.A, ControllerInput.B])
            if picked.get_input() == ControllerInput.B:
                return
            if picked.get_input() == ControllerInput.A:
                picked.get_selection().get_value()()
                Controller.clear_input_queue()
                time.sleep(0.2)

    def _browse_root(self):
        video_root = self._video_root()
        self._browse(video_root, video_root)

    def _show_controls(self):
        Display.display_message(
            Language.get(
                "videoControlsHelp",
                "Playback controls:\nB: Pause/Resume\nLeft/Right: Seek\nUp/Down: Prev/Next\nMENU: Exit player\n\nBrowser:\nX: Refresh\nB: Back",
            ),
            duration_ms=5000,
        )

    def _search_videos(self):
        query = OnScreenKeyboard().get_input(Language.get("videoSearch", "Video Search:"))
        if not query:
            return
        matches = self._search_entries(query)
        if not matches:
            Display.display_message(Language.get("noMatchingVideos", "No matching videos."))
            return
        selected = Selection(None, None, 0)
        view = ViewCreator.create_view(
            view_type=ViewType.ICON_AND_DESC,
            top_bar_text=Language.get("videoSearchTitle", "Video Search"),
            options=self._entries_to_options(matches),
            selected_index=selected.get_index(),
        )
        while selected is not None:
            picked = view.get_selection([ControllerInput.A, ControllerInput.B])
            if picked.get_input() == ControllerInput.B:
                return
            if picked.get_input() == ControllerInput.A:
                self._play_video(picked.get_selection().get_extra_data()["path"])
                return

    def _refresh_index(self):
        entries = self._build_video_index()
        self._write_video_index(entries)
        Display.display_message(
            Language.get("videoIndexUpdated", "Video index updated") + f"\n{len(entries)} files",
            duration_ms=2500,
        )

    def _browse(self, current_dir, root_dir):
        selected = Selection(None, None, 0)
        while selected is not None:
            entries = self._list_entries(current_dir, root_dir)
            options = self._entries_to_options(entries)

            view = ViewCreator.create_view(
                view_type=ViewType.ICON_AND_DESC,
                top_bar_text=os.path.basename(current_dir.rstrip("/")) or Language.get("videos", "Videos"),
                options=options,
                selected_index=selected.get_index(),
            )
            picked = view.get_selection([ControllerInput.A, ControllerInput.B, ControllerInput.X])
            if picked.get_input() == ControllerInput.X:
                self._refresh_index()
                selected = Selection(None, None, picked.get_index())
                continue
            if picked.get_input() == ControllerInput.B:
                if current_dir == root_dir:
                    return
                current_dir = os.path.dirname(current_dir.rstrip("/")) or root_dir
                selected = Selection(None, None, 0)
                continue
            if picked.get_input() == ControllerInput.A:
                entry = picked.get_selection().get_extra_data()
                kind = entry.get("kind")
                if kind == "up":
                    current_dir = os.path.dirname(current_dir.rstrip("/")) or root_dir
                    selected = Selection(None, None, 0)
                elif kind == "dir":
                    self._browse(entry["path"], root_dir)
                    selected = Selection(None, None, picked.get_index())
                elif kind == "file":
                    self._play_video(entry["path"])
                    return

    def _list_entries(self, current_dir, root_dir):
        entries = []
        if current_dir != root_dir:
            entries.append(
                {
                    "label": "..",
                    "description": Language.get("parentFolder", "Parent folder"),
                    "kind": "up",
                }
            )

        try:
            names = sorted(os.listdir(current_dir), key=str.lower)
        except OSError as e:
            PyUiLogger.get_logger().error(f"Cannot list {current_dir}: {e}")
            return entries

        for name in names:
            if name.startswith("."):
                continue
            path = os.path.join(current_dir, name)
            if os.path.isdir(path):
                entries.append(
                    {
                        "label": f"[{name}]",
                        "description": Language.get("folder", "Folder"),
                        "kind": "dir",
                        "path": path,
                    }
                )
            elif self._is_video_file(name):
                entries.append(
                    {
                        "label": name,
                        "description": Language.get("playVideo", "Play video"),
                        "kind": "file",
                        "path": path,
                    }
                )
        return entries

    def _entries_to_options(self, entries):
        options = []
        for entry in entries:
            options.append(
                GridOrListEntry(
                    primary_text=entry["label"],
                    value_text=None,
                    image_path=None,
                    image_path_selected=None,
                    description=entry.get("description"),
                    icon=None,
                    extra_data=entry,
                    value=0,
                )
            )
        return options

    def _search_entries(self, query):
        matches = []
        query = query.lower()
        for item in self._load_or_build_video_index():
            name = item.get("name", "")
            path = item.get("path", "")
            if query not in name.lower() or not os.path.isfile(path):
                continue
            rel_dir = item.get("folder", ".")
            matches.append(
                {
                    "label": name,
                    "description": Language.get("playVideo", "Play video") if rel_dir == "." else rel_dir,
                    "kind": "file",
                    "path": path,
                }
            )
        return matches

    def _load_or_build_video_index(self):
        entries = self._read_video_index()
        if entries is None:
            entries = self._build_video_index()
            self._write_video_index(entries)
        return entries

    def _read_video_index(self):
        try:
            if not os.path.isfile(VIDEO_CACHE):
                return None
            cache_mtime = os.path.getmtime(VIDEO_CACHE)
            root_mtime = os.path.getmtime(self._video_root())
            if root_mtime > cache_mtime:
                return None
            with open(VIDEO_CACHE, "r", encoding="utf-8") as f:
                data = json.load(f)
            entries = data.get("entries")
            return entries if isinstance(entries, list) else None
        except Exception as e:
            PyUiLogger.get_logger().error(f"Cannot read video index: {e}")
            return None

    def _write_video_index(self, entries):
        try:
            os.makedirs(os.path.dirname(VIDEO_CACHE), exist_ok=True)
            with open(VIDEO_CACHE, "w", encoding="utf-8") as f:
                json.dump({"created": int(time.time()), "entries": entries}, f)
        except Exception as e:
            PyUiLogger.get_logger().error(f"Cannot write video index: {e}")

    def _build_video_index(self):
        entries = []
        video_root = self._video_root()
        for dirpath, dirnames, filenames in os.walk(video_root):
            dirnames[:] = [name for name in dirnames if not name.startswith(".")]
            for name in sorted(filenames, key=str.lower):
                if name.startswith(".") or not self._is_video_file(name):
                    continue
                path = os.path.join(dirpath, name)
                try:
                    stat = os.stat(path)
                except OSError:
                    continue
                entries.append(
                    {
                        "name": name,
                        "path": path,
                        "folder": os.path.relpath(dirpath, video_root),
                        "mtime": int(stat.st_mtime),
                        "size": stat.st_size,
                    }
                )
        return entries

    def _is_video_file(self, name):
        _, ext = os.path.splitext(name.lower())
        return ext in VIDEO_EXTENSIONS

    def _play_video(self, path):
        from devices.miyoo_trim_common import MiyooTrimCommon

        if not os.path.isfile(MEDIA_LAUNCH):
            Display.display_message(Language.get("mediaLauncherMissing", "Media launcher missing."))
            return

        escaped = re.sub(r'([$`"\\])', r"\\\1", path)
        cmd = f'chmod a+x "{MEDIA_LAUNCH}"; "{MEDIA_LAUNCH}" "{escaped}"'
        Display.deinit_display()
        MiyooTrimCommon.write_cmd_to_run(cmd)
        Device.get_device().exit_pyui()
