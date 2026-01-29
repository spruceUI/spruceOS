import time
from functools import wraps

def limit_refresh(seconds=15):
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
            if now - last_called[0] >= seconds or getattr(wrapper, "_force_refresh", False):
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
