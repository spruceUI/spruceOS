"""Open disposable SQLite cache files, recreating them instead of migrating.

A cache is valid only if its ``PRAGMA user_version`` equals the schema version the code
expects. Anything else (an older or newer app version, a fresh empty file, a corrupt or
non-SQLite file) deletes the file and its journal siblings and creates the schema from
scratch. Callers then re-fill the cache from RA.

Connections are plain ``sqlite3`` connections with the default ``check_same_thread=True``:
use each one only on the thread that opened it, and open one per thread that needs the cache.
:func:`select_among` runs a query for a long list of IDs on any of them.
"""

from __future__ import annotations

import logging
import sqlite3
from collections.abc import Iterable
from pathlib import Path

logger = logging.getLogger(__name__)

# Files SQLite may leave next to a database (rollback journal, WAL, shared memory).
SIBLING_SUFFIXES = ("-journal", "-wal", "-shm")
BUSY_TIMEOUT_SECONDS = 5.0
QUERY_CHUNK = 500  # stay well below SQLite's bound-parameter limit


def _connect(path: Path) -> sqlite3.Connection:
    """Connect with the cache pragmas applied.

    ``journal_mode=DELETE`` because WAL needs shared memory and is unreliable on the FAT32
    cards Spruce devices use. Setting the journal mode also reads the file header, so a
    corrupt or non-SQLite file fails here with :class:`sqlite3.DatabaseError`.

    Args:
        path: Database file.

    Returns:
        The connection, with ``sqlite3.Row`` rows.

    Raises:
        sqlite3.DatabaseError: If the file is not a usable SQLite database.
    """
    connection = sqlite3.connect(str(path), timeout=BUSY_TIMEOUT_SECONDS)
    try:
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode=DELETE").fetchone()
        connection.execute("PRAGMA synchronous=NORMAL")
        connection.execute("PRAGMA foreign_keys=ON")
    except sqlite3.DatabaseError:
        connection.close()
        raise
    return connection


def delete_cache_files(path: Path) -> None:
    """Delete a cache database and any journal/WAL/shared-memory files next to it.

    Args:
        path: Database file (it need not exist).
    """
    for candidate in [path, *(path.with_name(path.name + s) for s in SIBLING_SUFFIXES)]:
        candidate.unlink(missing_ok=True)


def _create(path: Path, schema_version: int, ddl: str) -> sqlite3.Connection:
    """Create a fresh cache: run the DDL and stamp the schema version.

    Args:
        path: Database file (must not exist or be empty).
        schema_version: Version to store in ``PRAGMA user_version``.
        ddl: SQL script creating the schema.

    Returns:
        The connection.
    """
    connection = _connect(path)
    connection.executescript(ddl)
    connection.execute(f"PRAGMA user_version = {int(schema_version)}")
    connection.commit()
    return connection


def reset_cache(path: Path, *, schema_version: int, ddl: str) -> sqlite3.Connection:
    """Throw a cache away and create it empty.

    The caller must have closed every connection to ``path`` first.

    Args:
        path: Database file.
        schema_version: Expected schema version (must be at least 1).
        ddl: SQL script creating the schema.

    Returns:
        A connection to the new, empty cache.
    """
    delete_cache_files(path)
    return _create(path, schema_version, ddl)


def open_cache(path: Path, *, schema_version: int, ddl: str) -> sqlite3.Connection:
    """Open a cache, recreating it if it is missing, outdated or unreadable.

    Args:
        path: Database file; parent directories are created.
        schema_version: Expected schema version (must be at least 1, since a fresh SQLite
            file reports 0).
        ddl: SQL script creating the schema from nothing.

    Returns:
        A connection to a cache whose schema matches ``schema_version``.

    Raises:
        ValueError: If ``schema_version`` is less than 1.
    """
    if schema_version < 1:
        raise ValueError("schema_version must be at least 1")
    path.parent.mkdir(parents=True, exist_ok=True)
    existed = path.exists() and path.stat().st_size > 0
    try:
        connection = _connect(path)
        found = int(connection.execute("PRAGMA user_version").fetchone()[0])
    except sqlite3.DatabaseError as exc:
        reason = f"unreadable ({exc})"
    else:
        if found == schema_version:
            return connection
        connection.close()
        reason = f"schema version {found}, expected {schema_version}"
    if existed:
        logger.info("Recreating cache %s: %s", path, reason)
    else:
        logger.info("Creating cache %s", path)
    return reset_cache(path, schema_version=schema_version, ddl=ddl)


def select_among(
    connection: sqlite3.Connection, query: str, ids: Iterable[object], *, column: str
) -> list[sqlite3.Row]:
    """Run a query for a list of IDs, a chunk at a time.

    Args:
        connection: Open connection.
        query: SQL ending in ``WHERE`` or ``AND``; ``<column> IN (...)`` is appended.
        ids: Values of ``column`` to select.
        column: The column the IDs are for.

    Returns:
        The rows of every chunk.
    """
    ids = list(ids)
    rows: list[sqlite3.Row] = []
    for start in range(0, len(ids), QUERY_CHUNK):
        chunk = ids[start : start + QUERY_CHUNK]
        marks = ",".join("?" * len(chunk))
        sql = f"{query} {column} IN ({marks})"  # values are bound, never interpolated
        rows += connection.execute(sql, chunk).fetchall()
    return rows
