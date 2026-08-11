import queue
import threading

from utils.logger import PyUiLogger


class RomListVerifier:
    """
    Confirms cached rom listings against what is actually in the folder.

    The cached listing is keyed off the folder's modification date, and that date
    on its own is not trustworthy. Archive tools (7-Zip, WinRAR, Windows' built in
    extract) write the date stored inside the archive back onto the folder after
    they have finished extracting into it, so a folder can gain games while its
    date stays put or even moves backwards. When that happens the cache looks
    valid but isn't, and the new games never show up.

    Reading the folder is the only reliable way to tell, but doing that before
    every menu draws would make opening a system slower for everyone. So the
    cached listing is shown straight away and confirmed on a worker thread. If it
    turns out to be wrong the cache is corrected and the generation counter moves,
    which the rom menus watch so they can rebuild themselves.
    """

    _queue = queue.Queue()
    _worker = None
    _worker_lock = threading.Lock()

    _state_lock = threading.Lock()
    _generation = 0
    _queued = set()

    @classmethod
    def generation(cls):
        """Moves every time a cached listing is found to be out of date."""
        with cls._state_lock:
            return cls._generation

    @classmethod
    def schedule(cls, key, verify):
        """
        Queue verify() for key. Keys already waiting are ignored, so a menu that
        redraws every frame doesn't pile up thousands of identical checks.
        """
        with cls._state_lock:
            if key in cls._queued:
                return
            cls._queued.add(key)

        cls._ensure_worker()
        cls._queue.put((key, verify))

    @classmethod
    def _ensure_worker(cls):
        with cls._worker_lock:
            if cls._worker is None or not cls._worker.is_alive():
                cls._worker = threading.Thread(
                    target=cls._worker_loop,
                    name="RomListVerifierThread",
                    daemon=True,
                )
                cls._worker.start()

    @classmethod
    def _worker_loop(cls):
        while True:
            key, verify = cls._queue.get()
            changed = False

            try:
                changed = verify()
            except Exception as e:
                PyUiLogger.get_logger().error(f"Error verifying rom list for '{key}': {e}")

            with cls._state_lock:
                cls._queued.discard(key)
                if changed:
                    cls._generation += 1

            if changed:
                PyUiLogger.get_logger().info(f"Rom list was out of date, refreshed [{key}]")
