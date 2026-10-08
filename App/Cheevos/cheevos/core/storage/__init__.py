"""Disposable SQLite caches: RA data (``data.db``) and images (``media.db``).

Nothing here is user data. Any cache file may be deleted at any time; opening it recreates it,
and a schema version change or corruption recreates it as well (there are no migrations). See
.agents/sync-and-storage.md.
"""
