import threading
import time
from functools import wraps

def limit_refresh(seconds=15, fast_seconds=None, fast_while=None, background=False):
    """Cache the result for `seconds`.

    fast_while names an attribute on the first argument (self or cls) holding a
    time.time() deadline; while now < deadline the window is `fast_seconds`
    instead. A WiFi status that is cached for 15 s is fine in steady state, but
    right after the user picks a network or toggles the radio the row and the
    top-bar icon must follow within a second, not half a minute - so the device
    sets the deadline (DeviceCommon.note_wifi_change) and the caches run fast
    until it passes. force_refresh() still drops the value once, immediately.

    background=True is for reads that block, such as a command the UI draws from
    every frame: once a value is cached, a stale or forced call returns it at once
    and refreshes in a background thread, one refresh at a time. While a refresh
    is running the call stays due, so a change asked for meanwhile is read by the
    next refresh. Only the first call, with nothing cached, waits for the result.
    """
    def decorator(func):

        # Detect classmethod and unwrap
        is_classmethod = isinstance(func, classmethod)
        if is_classmethod:
            orig_func = func.__func__
        else:
            orig_func = func

        last_called = [0]
        last_result = [None]
        has_result = [False]
        refreshing = [False]
        lock = threading.Lock()

        def refresh_in_background(args, kwargs):
            try:
                last_result[0] = orig_func(*args, **kwargs)
            except Exception as e:
                from utils.logger import PyUiLogger
                PyUiLogger.get_logger().error(f"Background refresh of {getattr(orig_func, '__name__', 'a cached read')} failed: {e}")
            finally:
                with lock:
                    refreshing[0] = False

        @wraps(orig_func)
        def wrapper(*args, **kwargs):
            now = time.monotonic()
            window = seconds
            if fast_while and fast_seconds is not None and args:
                try:
                    if getattr(args[0], fast_while, 0) > time.time():
                        window = fast_seconds
                except Exception:
                    pass
            # A cold boot can still be at epoch + a few seconds. The first read must
            # run even then, and NTP must not extend or expire a duration cache.
            if (not has_result[0] or now - last_called[0] >= window
                    or getattr(wrapper, "_force_refresh", False)):
                if background and has_result[0]:
                    with lock:
                        if not refreshing[0]:
                            refreshing[0] = True
                            last_called[0] = now
                            wrapper._force_refresh = False
                            threading.Thread(target=refresh_in_background, args=(args, kwargs), daemon=True).start()
                else:
                    # The Wi-Fi warm-up and first frame can arrive together. Only
                    # one initial read runs; both callers need its actual result.
                    with lock:
                        now = time.monotonic()
                        if (not has_result[0] or now - last_called[0] >= window
                                or getattr(wrapper, "_force_refresh", False)):
                            last_result[0] = orig_func(*args, **kwargs)
                            last_called[0] = now
                            has_result[0] = True
                            wrapper._force_refresh = False
            return last_result[0]

        # Add method to force refresh
        def force():
            wrapper._force_refresh = True

        wrapper.force_refresh = force

        # If it was a classmethod, return it wrapped back as classmethod
        if is_classmethod:
            return classmethod(wrapper)

        return wrapper

    return decorator
