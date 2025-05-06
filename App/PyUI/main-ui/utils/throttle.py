import time
from functools import wraps

def limit_refresh(seconds=15):
    def decorator(func):
        last_called = [0]
        last_result = [None]

        @wraps(func)
        def wrapper(*args, **kwargs):
            now = time.time()
            if now - last_called[0] >= seconds or getattr(wrapper, "_force_refresh", False):
                last_called[0] = now
                last_result[0] = func(*args, **kwargs)
                wrapper._force_refresh = False
            return last_result[0]

        # Add method to force refresh
        def force():
            wrapper._force_refresh = True

        wrapper.force_refresh = force
        return wrapper
    return decorator