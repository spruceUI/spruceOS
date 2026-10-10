"""First-run setup: find the username, get the Web API key (file or keyboard), validate it."""

from __future__ import annotations

import dataclasses
from collections.abc import Callable

from cheevos.core.credentials import (
    looks_like_api_key,
    read_api_key,
    read_username,
    save_api_key,
)
from cheevos.core.sync.session import Credentials
from cheevos.platform.paths import Paths
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui import primitives as ui
from cheevos.ui.pyui.primitives import Button
from cheevos.ui.screens.common import busy, message, prompt

# (username, key) -> True (accepted), False (rejected), None (couldn't reach RA).
KeyValidator = Callable[[str, str], bool | None]

# PyUI's keyboard: A types the highlighted key, and these do the rest.
KEYBOARD_HINTS = (
    (Button.START, strings.HINT_DONE),
    (Button.B, strings.HINT_DELETE),
    (Button.L1, strings.HINT_SHIFT),
    (Button.R1, strings.HINT_CAPS),
)


def ensure_credentials(paths: Paths, validate: KeyValidator) -> Credentials | None:
    """Return the account to use, asking for the API key if the key file has none.

    A key in the file is trusted as long as it has a key's shape; if RA rejects it, the first
    sync says so and Start offers to enter a new one.

    Args:
        paths: Device paths.
        validate: Checks a key with RA.

    Returns:
        Credentials, or ``None`` if setup cannot finish (no username, or the user exited).
    """
    username = read_username(paths)
    if not username:
        message(strings.SETUP, [strings.NO_USERNAME])
        return None
    key = read_api_key(paths)
    if key and looks_like_api_key(key):
        return Credentials(username, key)
    file = paths.api_key_file.relative_to(paths.sdcard)
    problem = strings.KEY_FILE_INVALID.format(path=file) if key else strings.KEY_NEEDED
    key = ask_for_key(paths, username, validate, problem)
    return Credentials(username, key) if key else None


def ask_for_key(paths: Paths, username: str, validate: KeyValidator, problem: str) -> str | None:
    """Explain what's needed until a key is typed (A) or the user leaves (B).

    Args:
        paths: Device paths.
        username: RA username.
        validate: Checks a key with RA.
        problem: First paragraph: no key yet, or the file doesn't hold one.

    Returns:
        The key, or ``None`` if the user exited.
    """
    file = paths.api_key_file.relative_to(paths.sdcard)
    paragraphs = [problem, strings.KEY_WHERE, strings.KEY_HOW.format(path=file)]
    hints = [(Button.A, strings.ENTER_KEY), (Button.B, strings.EXIT)]
    while prompt(strings.SETUP, paragraphs, hints) is Button.A:
        key = enter_key(paths, username, validate)
        if key:
            return key
    return None


def change_key(ctx: AppContext) -> None:
    """Type a new key (Settings, or Start after RA rejected the key) and sync with it.

    Args:
        ctx: App context.
    """
    entered = enter_key(ctx.paths, ctx.credentials.username, ctx.validate_key)
    if entered:
        ctx.credentials = dataclasses.replace(ctx.credentials, api_key=entered)
        ctx.start_sync()


def enter_key(paths: Paths, username: str, validate: KeyValidator) -> str | None:
    """Type a key on the on-screen keyboard, validate it, and save it.

    A key that can't be verified because RA is unreachable is saved anyway; the next sync
    reports if RA rejects it.

    Args:
        paths: Device paths.
        username: RA username.
        validate: Checks a key with RA.

    Returns:
        The saved key, or ``None`` if cancelled, malformed or rejected.
    """
    entered = ui.ask_text(strings.KEY_PROMPT, secret=True, hints=KEYBOARD_HINTS)
    if entered is None:
        return None
    key = entered.strip()
    if not looks_like_api_key(key):
        message(strings.KEY_PROMPT, [strings.KEY_INVALID_FORMAT])
        return None
    busy(strings.KEY_PROMPT, strings.KEY_CHECKING)
    verdict = validate(username, key)
    if verdict is False:
        message(strings.KEY_PROMPT, [strings.KEY_REJECTED])
        return None
    save_api_key(paths, key)
    if verdict is None:
        message(strings.KEY_PROMPT, [strings.KEY_UNVERIFIED])
    return key
