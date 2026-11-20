import ctypes
import os
import select
import struct
import threading
import time

from devices.utils.polling_file_watcher import PollingFileWatcher
from utils.logger import PyUiLogger


class INotifyFileWatcher():
    """One inotify thread for every watched file, so no watcher wakes on a timer.

    FileWatcher uses it when launch.sh exports FILE_WATCH_EVENT_TYPE=INOTIFY.
    """
    # A change inotify cannot see (a write through mmap, say) still shows this late.
    BACKSTOP_SEC = 5.0
    # The folder is watched, since spruce replaces these files by renaming a temp file over them.
    _MASK = 0x4 | 0x8 | 0x80 | 0x100 | 0x01000000  # ATTRIB CLOSE_WRITE MOVED_TO CREATE, ONLYDIR
    _Q_OVERFLOW = 0x4000
    _IGNORED = 0x8000
    _EVENT = struct.Struct("iIII")

    _lock = threading.Lock()
    _fd = None  # None until first used, -1 when inotify is unavailable
    _add_watch = None
    _thread = None
    _folders = {}  # folder -> watch descriptor
    _watches = []  # [path, folder, name, callback, stop_event, signature]

    def start_file_watcher(self, path, callback, interval=1.0, repeat_trigger_for_mtime_granularity_issues=False):
        stop_event = threading.Event()
        # Each write is its own event, so the mtime repeat is not needed.
        if self.watch(path, callback, stop_event):
            return self.thread(), stop_event
        return PollingFileWatcher().start_file_watcher(
            path, callback, interval, repeat_trigger_for_mtime_granularity_issues)

    @classmethod
    def watch(cls, path, callback, stop_event=None):
        """Calls callback after each change to path. False when inotify is unavailable: poll instead."""
        path = os.path.abspath(path)
        folder, name = os.path.split(path)
        with cls._lock:
            if not cls._start() or cls._watch_folder(folder) < 0:
                return False
            cls._watches.append([path, folder, name, callback, stop_event, cls._signature(path)])
        return True

    @classmethod
    def thread(cls):
        return cls._thread

    @classmethod
    def _start(cls):
        if cls._fd is not None:
            return cls._fd >= 0
        cls._fd = -1
        try:
            libc = ctypes.CDLL(None, use_errno=True)
            try:
                fd = libc.inotify_init1(os.O_CLOEXEC)
            except AttributeError:
                fd = libc.inotify_init()
            add_watch = libc.inotify_add_watch
            add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
            add_watch.restype = ctypes.c_int
        except (OSError, AttributeError) as e:
            PyUiLogger.get_logger().warning(f"No inotify, so file watchers poll: {e}")
            return False
        if fd < 0:
            PyUiLogger.get_logger().warning(f"inotify_init failed (errno {ctypes.get_errno()}), so file watchers poll")
            return False
        cls._fd, cls._add_watch = fd, add_watch
        cls._thread = threading.Thread(target=cls._run, name="FileEvents", daemon=True)
        cls._thread.start()
        PyUiLogger.get_logger().info("File watchers use inotify")
        return True

    @classmethod
    def _watch_folder(cls, folder, quiet=False):
        wd = cls._folders.get(folder, -1)
        if wd < 0:
            wd = cls._add_watch(cls._fd, os.fsencode(folder), cls._MASK)
            if wd < 0:
                if not quiet:
                    PyUiLogger.get_logger().warning(
                        f"Cannot watch {folder} (errno {ctypes.get_errno()}), so its watchers poll")
                return wd
            cls._folders[folder] = wd
        return wd

    @staticmethod
    def _signature(path):
        try:
            st = os.stat(path)
        except OSError:
            return None
        return (st.st_ino, st.st_size, st.st_mtime_ns)

    @classmethod
    def _run(cls):
        backstop_at = time.monotonic() + cls.BACKSTOP_SEC
        while True:
            try:
                wait = max(0.0, backstop_at - time.monotonic())
                if select.select([cls._fd], [], [], wait)[0]:
                    cls._dispatch(cls._read_events())
                if time.monotonic() >= backstop_at:
                    cls._dispatch(None)
                    backstop_at = time.monotonic() + cls.BACKSTOP_SEC
            except Exception as e:  # one bad read or callback must not end the watching
                PyUiLogger.get_logger().warning(f"File events: {e}")
                time.sleep(1.0)

    @classmethod
    def _read_events(cls):
        """The (folder, name) pairs that changed, or None when the queue overflowed: check them all."""
        data = os.read(cls._fd, 65536)
        changed = set()
        offset = 0
        while offset + cls._EVENT.size <= len(data):
            wd, mask, _cookie, length = cls._EVENT.unpack_from(data, offset)
            start = offset + cls._EVENT.size
            name = data[start:start + length].rstrip(b"\0")
            offset = start + length
            if mask & cls._Q_OVERFLOW:
                return None
            with cls._lock:
                folder = next((f for f, w in cls._folders.items() if w == wd), None)
                if folder is not None and mask & cls._IGNORED:
                    del cls._folders[folder]  # the folder went away; the backstop adds it back
            if folder is not None and name:
                changed.add((folder, os.fsdecode(name)))
        return changed

    @classmethod
    def _dispatch(cls, changed):
        """Calls back each watch named in changed, or with None each whose file is not as last seen."""
        due = []
        with cls._lock:
            cls._watches = [w for w in cls._watches if w[4] is None or not w[4].is_set()]
            if changed is None:
                for folder in {w[1] for w in cls._watches} - set(cls._folders):
                    cls._watch_folder(folder, quiet=True)
            for w in cls._watches:
                if changed is not None and (w[1], w[2]) not in changed:
                    continue
                sig = cls._signature(w[0])
                if changed is None and sig == w[5]:
                    continue
                w[5] = sig
                due.append(w[3])
        for callback in due:
            try:
                callback()
            except Exception as e:
                PyUiLogger.get_logger().warning(f"File watcher callback failed: {e}")
