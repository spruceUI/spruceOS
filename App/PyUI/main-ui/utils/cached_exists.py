import os
from typing import Dict, Set


class CachedExists:
    """
    Class-level cached replacement for os.path.exists().

    - One os.listdir() per directory
    - Subsequent checks are O(1)
    - Shared cache across the entire process
    """

    _dir_cache: Dict[str, Set[str]] = {}

    @classmethod
    def exists(cls, path: str) -> bool:
        # Normalize path
        path = os.path.normpath(path)

        directory, filename = os.path.split(path)

        # Fallback for weird paths (root, no filename, etc)
        if not directory or not filename:
            return os.path.exists(path)

        # Cache hit
        cached = cls._dir_cache.get(directory)
        if cached is not None:
            return filename in cached

        # Cache miss: list directory once
        try:
            files = set(os.listdir(directory))
        except (FileNotFoundError, NotADirectoryError, PermissionError):
            # Cache negative result to avoid re-hitting disk
            cls._dir_cache[directory] = set()
            return False

        cls._dir_cache[directory] = files
        return filename in files

    @classmethod
    def invalidate_dir(cls, directory: str):
        """Invalidate a single directory cache."""
        directory = os.path.normpath(directory)
        cls._dir_cache.pop(directory, None)

    @classmethod
    def clear(cls):
        """Clear all cached directories."""
        cls._dir_cache.clear()
