"""Keep the Web API key out of every log line.

:func:`install_redaction` wraps the logging record factory, so every record from any logger
(``cheevos.*`` and PyUI's alike) is scrubbed when it is created, whichever handlers exist now or
are added later. :class:`RedactingFilter` applies the same scrubbing to a single handler or
logger when that is preferred.
"""

from __future__ import annotations

import logging
import re
import threading
from collections.abc import Callable

MASK = "***"
_QUERY_KEY = re.compile(r"(?<![A-Za-z0-9_])y=[^&\s'\"]+")
_secrets: set[str] = set()
_lock = threading.Lock()
_installed: tuple[Callable[..., logging.LogRecord], Callable[..., logging.LogRecord]] | None = None


def redact(text: str) -> str:
    """Mask registered secrets and any ``y=<value>`` query parameter in ``text``.

    Args:
        text: Text that may contain a key.

    Returns:
        The text with secrets replaced by ``***``.
    """
    for secret in _secrets:
        text = text.replace(secret, MASK)
    return _QUERY_KEY.sub(f"y={MASK}", text)


def redact_record(record: logging.LogRecord) -> None:
    """Scrub a log record in place: its message, traceback and stack.

    The message and arguments are merged when anything is masked. A traceback is formatted
    now and kept scrubbed in ``exc_text``, which handlers then print instead of formatting it
    again.

    Args:
        record: The record to scrub.
    """
    try:
        message = record.getMessage()
    except (TypeError, ValueError):
        message = str(record.msg)
    cleaned = redact(message)
    if cleaned != message:
        record.msg = cleaned
        record.args = None
    if isinstance(record.exc_info, tuple) and record.exc_info[0] and not record.exc_text:
        trace = logging.Formatter().formatException(record.exc_info)
        if redact(trace) != trace:
            record.exc_text = redact(trace)
    if record.stack_info:
        record.stack_info = redact(record.stack_info)


class RedactingFilter(logging.Filter):
    """Logging filter that scrubs records passing through a handler or logger."""

    def filter(self, record: logging.LogRecord) -> bool:
        """Scrub ``record`` and let it through.

        Args:
            record: The record.

        Returns:
            Always ``True``.
        """
        redact_record(record)
        return True


def install_redaction(api_key: str) -> None:
    """Register ``api_key`` as a secret and make sure every new log record is scrubbed.

    Safe to call repeatedly (e.g. when the user enters a new key): the record factory is
    wrapped only once.

    Args:
        api_key: The Web API key; empty values are ignored.
    """
    global _installed  # noqa: PLW0603 — process-wide logging hook, installed once
    with _lock:
        if api_key:
            _secrets.add(api_key)
        if _installed is not None:
            return
        previous: Callable[..., logging.LogRecord] = logging.getLogRecordFactory()

        def factory(*args: object, **kwargs: object) -> logging.LogRecord:
            """Create a record with the previous factory, then scrub it."""
            record = previous(*args, **kwargs)
            redact_record(record)
            return record

        logging.setLogRecordFactory(factory)
        _installed = (factory, previous)


def uninstall_redaction() -> None:
    """Put the record factory back and forget the secrets, when the app leaves PyUI's process.

    The factory is process-wide: inside PyUI it would otherwise keep running this module for
    every PyUI record after the app has gone (.agents/pyui.md, "In-process sessions"). A factory
    wrapped again by someone else since is left in place.
    """
    global _installed  # noqa: PLW0603 — process-wide logging hook
    with _lock:
        _secrets.clear()
        if _installed is None:
            return
        factory, previous = _installed
        if logging.getLogRecordFactory() is factory:
            logging.setLogRecordFactory(previous)
        _installed = None
