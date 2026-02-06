import time
from functools import wraps
from typing import Any

def limit_refresh(seconds=15):
    def decorator(func):

        # Detect classmethod and unwrap
        is_classmethod = isinstance(func, classmethod)
        if is_classmethod:
            orig_func = func.__func__
        else:
            orig_func = func

        last_called: list[float] = [0.0]
        last_result: list[Any] = [None]
        force_state = {"force": False}

        @wraps(orig_func)
        def wrapper(*args, **kwargs):
            now = time.time()
            if now - last_called[0] >= seconds or force_state["force"]:
                last_called[0] = now
                last_result[0] = orig_func(*args, **kwargs)
                force_state["force"] = False
            return last_result[0]

        # Add method to force refresh
        def force():
            force_state["force"] = True

        wrapper_any: Any = wrapper
        wrapper_any.force_refresh = force

        # If it was a classmethod, return it wrapped back as classmethod
        if is_classmethod:
            return classmethod(wrapper)

        return wrapper

    return decorator
