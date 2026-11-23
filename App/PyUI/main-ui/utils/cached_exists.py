import os
from typing import Dict, List


class CachedExists:
    """
    Class-level cached replacement for os.path.exists().

    - One os.listdir() per directory
    - Subsequent checks are O(1)
    - Shared cache across the entire process
    """

    # directory -> lowercased name -> names as they are on disk
    _dir_cache: Dict[str, Dict[str, List[str]]] = {}

    @classmethod
    def _names(cls, directory: str) -> Dict[str, List[str]]:
        cached = cls._dir_cache.get(directory)
        if cached is not None:
            return cached

        names: Dict[str, List[str]] = {}
        try:
            for f in os.listdir(directory):
                names.setdefault(f.lower(), []).append(f)
        except (FileNotFoundError, NotADirectoryError, PermissionError):
            # Cache negative result to avoid re-hitting disk
            pass

        cls._dir_cache[directory] = names
        return names

    @classmethod
    def exists(cls, path: str) -> bool:
        # Normalize path
        path = os.path.normpath(path)

        directory, filename = os.path.split(path)

        # Fallback for weird paths (root, no filename, etc)
        if not directory or not filename:
            return os.path.exists(path)

        return filename in cls._names(directory).get(filename.lower(), ())

    @classmethod
    def matches_ignore_case(cls, directory: str, filename: str) -> List[str]:
        return cls._names(os.path.normpath(directory)).get(filename.lower(), [])

    @classmethod
    def invalidate_dir(cls, directory: str):
        """Invalidate a single directory cache."""
        directory = os.path.normpath(directory)
        cls._dir_cache.pop(directory, None)

    @classmethod
    def clear(cls):
        """Clear all cached directories."""
        cls._dir_cache.clear()
