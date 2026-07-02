import os
import re

from controller.controller_inputs import ControllerInput
from devices.device import Device
from devices.miyoo_trim_common import MiyooTrimCommon
from display.display import Display
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType

VIDEO_EXTENSIONS = {
    ".mp4", ".mkv", ".avi", ".mov", ".flv", ".ts", ".webm",
    ".m4v", ".wmv", ".mpeg", ".mpg", ".3gp",
}
VIDEO_ROOTS = (
    "/mnt/SDCARD/Roms/MEDIA",
    "/mnt/SDCARD/Roms/media",
    "/mnt/SDCARD/Roms/VIDEOS",
    "/mnt/SDCARD/Roms/videos",
)


class VideoPlayerApp:
    def run(self, _input=None):
        root = self._default_root()
        if root is None:
            Display.display_message("No video folder found.\nAdd files to Roms/MEDIA/")
            return
        self._browse(root, root)

    def _default_root(self):
        for path in VIDEO_ROOTS:
            if os.path.isdir(path):
                return path
        return None

    def _browse(self, current_dir, root_dir):
        selected = Selection(None, None, 0)
        while selected is not None:
            entries = self._list_entries(current_dir, root_dir)
            if not entries:
                Display.display_message("No videos in this folder.")
                if current_dir == root_dir:
                    return
                current_dir = os.path.dirname(current_dir.rstrip("/")) or root_dir
                selected = Selection(None, None, 0)
                continue

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

            view = ViewCreator.create_view(
                view_type=ViewType.ICON_AND_DESC,
                top_bar_text=os.path.basename(current_dir.rstrip("/")) or "Videos",
                options=options,
                selected_index=selected.get_index(),
            )
            picked = view.get_selection([ControllerInput.A, ControllerInput.B])
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
                    "description": "Parent folder",
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
                        "description": "Folder",
                        "kind": "dir",
                        "path": path,
                    }
                )
            elif self._is_video_file(name):
                entries.append(
                    {
                        "label": name,
                        "description": "Play video",
                        "kind": "file",
                        "path": path,
                    }
                )
        return entries

    def _is_video_file(self, name):
        _, ext = os.path.splitext(name.lower())
        return ext in VIDEO_EXTENSIONS

    def _play_video(self, path):
        device = Device.get_device()
        width = device.screen_width()
        height = device.screen_height()
        escaped = re.sub(r'([$`"\\])', r"\\\1", path)
        emu_dir = "/mnt/SDCARD/Emu/MEDIA"
        cmd = (
            f'export PATH="{emu_dir}/bin64:$PATH"; '
            f'export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:{emu_dir}/lib64"; '
            f'cd "{emu_dir}"; '
            f'/mnt/SDCARD/spruce/bin64/gptokeyb -k "ffplay" -c "./bin64/ffplay.gptk" & '
            f"sleep 1; "
            f'ffplay -x {width} -y {height} -fs -loglevel 24 -i "{escaped}"; '
            f'kill -9 "$(pidof gptokeyb)" 2>/dev/null'
        )
        Display.deinit_display()
        MiyooTrimCommon.write_cmd_to_run(cmd)
        device.exit_pyui()
