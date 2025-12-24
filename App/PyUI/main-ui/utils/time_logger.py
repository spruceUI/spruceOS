import time
from contextlib import contextmanager

@contextmanager
def log_timing(label, logger):
    start = time.perf_counter()
    #logger.info(f"{label} started")
    try:
        yield
    finally:
        logger.info(f"{label} completed in {time.perf_counter() - start:.3f}s")
