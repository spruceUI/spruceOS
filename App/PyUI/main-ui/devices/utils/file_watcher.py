import ctypes
import os
import select
import struct
import threading
import time

from utils.logger import PyUiLogger


class FileEvents():
    """One inotify thread for every watched file, so no watcher wakes on a timer.

    Off unless the device scripts turn it on: launch.sh exports PYUI_FILE_EVENTS=1.
    """
    ENV = "PYUI_FILE_EVENTS"
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

    @classmethod
    def enabled(cls):
        return os.environ.get(cls.ENV) == "1"

    @classmethod
    def watch(cls, path, callback, stop_event=None):
        """Calls callback after each change to path. False when off or unavailable: poll instead."""
        if not cls.enabled():
            return False
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


class FileWatcher():

    def watch_file(self, path, callback, interval, repeat_trigger_for_mtime_granularity_issues, stop_event=None):
        last_mtime = None
        prev_loop_executed_counter = 0.0
        try:
            last_mtime = os.stat(path).st_mtime_ns
        except OSError:
            PyUiLogger.get_logger().warning(f"{path} not found for file watcher; waiting for it to appear.")
        while stop_event is None or not stop_event.is_set():
            try:
                mtime = os.stat(path).st_mtime_ns
                if last_mtime is None:
                    PyUiLogger.get_logger().info(f"{path} appeared.")
                    last_mtime = mtime
                    callback()
                    if repeat_trigger_for_mtime_granularity_issues:
                        prev_loop_executed_counter = 2.0
                elif mtime != last_mtime:
                    PyUiLogger.get_logger().info(f"{path} detection changed.")
                    last_mtime = mtime
                    callback()
                    if repeat_trigger_for_mtime_granularity_issues:
                        prev_loop_executed_counter = 2.0
                elif(prev_loop_executed_counter > 0.0):
                    callback()
                    prev_loop_executed_counter -= interval
            except FileNotFoundError:
                PyUiLogger.get_logger().warning(f"{path} not found for file watcher.")
            if stop_event is not None:
                stop_event.wait(interval)
            else:
                time.sleep(interval)

    def start_file_watcher(self, path, callback, interval=1.0, repeat_trigger_for_mtime_granularity_issues=False):
        stop_event = threading.Event()
        # With file events each write is its own event, so the mtime repeat is not needed.
        if FileEvents.watch(path, callback, stop_event):
            return FileEvents.thread(), stop_event
        thread = threading.Thread(
            target=self.watch_file,
            args=(path, callback, interval, repeat_trigger_for_mtime_granularity_issues, stop_event),
            daemon=True
        )
        thread.start()
        return thread, stop_event
