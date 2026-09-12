import time
from functools import wraps

def limit_refresh(seconds=15, fast_seconds=None, fast_while=None):
    """Cache the result for `seconds`.

    fast_while names an attribute on the first argument (self or cls) holding a
    time.time() deadline; while now < deadline the window is `fast_seconds`
    instead. A WiFi status that is cached for 15 s is fine in steady state, but
    right after the user picks a network or toggles the radio the row and the
    top-bar icon must follow within a second, not half a minute - so the device
    sets the deadline (DeviceCommon.note_wifi_change) and the caches run fast
    until it passes. force_refresh() still drops the value once, immediately.
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

        @wraps(orig_func)
        def wrapper(*args, **kwargs):
            now = time.time()
            window = seconds
            if fast_while and fast_seconds is not None and args:
                try:
                    if getattr(args[0], fast_while, 0) > now:
                        window = fast_seconds
                except Exception:
                    pass
            if now - last_called[0] >= window or getattr(wrapper, "_force_refresh", False):
                last_called[0] = now
                last_result[0] = orig_func(*args, **kwargs)
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
