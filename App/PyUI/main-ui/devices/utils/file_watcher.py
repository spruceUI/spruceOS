import os

from devices.utils.inotify_file_watcher import INotifyFileWatcher
from devices.utils.polling_file_watcher import PollingFileWatcher


class FileWatcher():
    """Starts the watcher the device scripts chose: launch.sh exports FILE_WATCH_EVENT_TYPE."""
    INOTIFY = "INOTIFY"

    def start_file_watcher(self, path, callback, interval=1.0, repeat_trigger_for_mtime_granularity_issues=False):
        file_event_watch_type = os.environ.get("FILE_WATCH_EVENT_TYPE")
        if self.INOTIFY == file_event_watch_type:
            watcher = INotifyFileWatcher()
        else:
            watcher = PollingFileWatcher()
        return watcher.start_file_watcher(path, callback, interval, repeat_trigger_for_mtime_granularity_issues)
