"""Settings: spoilers, auto-sync, sync actions, key and cache."""

from __future__ import annotations

import dataclasses
from collections.abc import Callable

from cheevos.core.settings import DescriptionHiding
from cheevos.ui import format as fmt
from cheevos.ui import strings
from cheevos.ui.context import AppContext
from cheevos.ui.pyui.primitives import Button
from cheevos.ui.pyui.views import MenuItem, choose
from cheevos.ui.screens.common import message, pick, prompt
from cheevos.ui.screens.setup import change_key


def _on_off(value: bool) -> str:  # noqa: FBT001 — formats a flag
    """Format a boolean setting.

    Args:
        value: The setting.

    Returns:
        ``"On"`` or ``"Off"``.
    """
    return strings.ON if value else strings.OFF


def _items(ctx: AppContext) -> list[MenuItem]:
    """Build the settings rows with their current values.

    Args:
        ctx: App context.

    Returns:
        Rows.
    """
    settings = ctx.settings
    tail = ctx.credentials.api_key[-4:]
    return [
        MenuItem(
            strings.HIDE_LOCKED,
            strings.HIDE_LOCKED_HINTS[settings.hide_descriptions.value],
            ctx.icon("lock"),
            strings.HIDE_LOCKED_MODES[settings.hide_descriptions.value],
            "spoilers",
        ),
        MenuItem(strings.AUTO_SYNC, "", ctx.icon("zap"), _on_off(settings.auto_sync), "auto"),
        *_proxy_rows(ctx),
        MenuItem(strings.SYNC_NOW, strings.SYNC_NOW_HINT, ctx.icon("reload"), key="sync"),
        _download_all_row(ctx),
        MenuItem(
            strings.API_KEY, strings.API_KEY_SET.format(tail=tail), ctx.icon("info-box"), key="key"
        ),
        MenuItem(
            strings.CLEAR_IMAGES,
            strings.CLEAR_IMAGES_SIZE.format(size=fmt.size(ctx.media_cache.size_bytes())),
            ctx.icon("chart"),
            key="clear",
        ),
    ]


def _download_all_row(ctx: AppContext) -> MenuItem:
    """Offer "Download every game", or a way to stop one that hasn't finished.

    Args:
        ctx: App context.

    Returns:
        The row.
    """
    if ctx.full_download_pending():
        hint = strings.DOWNLOAD_ALL_STOP_HINT
        return MenuItem(strings.DOWNLOAD_ALL_STOP, hint, ctx.icon("download"), key="stop")
    return MenuItem(
        strings.DOWNLOAD_ALL, strings.DOWNLOAD_ALL_HINT, ctx.icon("download"), key="full"
    )


def _proxy_rows(ctx: AppContext) -> list[MenuItem]:
    """Describe RAOfflineProxy, if installed: on or off, online, queued unlocks, cached games.

    Args:
        ctx: App context.

    Returns:
        One row, or none without the proxy.
    """
    if not ctx.proxy.installed():
        return []
    if not ctx.proxy.enabled():
        return [MenuItem(strings.PROXY, strings.PROXY_OFF, ctx.icon("cloud"), key="proxy")]
    online = ctx.proxy.online()
    state = {True: strings.PROXY_ONLINE, False: strings.PROXY_OFFLINE}.get(
        online, strings.PROXY_UNKNOWN
    )
    waiting = len(ctx.pending_awards())
    status = strings.PROXY_STATUS.format(
        state=state,
        waiting=fmt.count(strings.PROXY_WAITING, waiting),
        cached=fmt.count(strings.PROXY_CACHED, len(ctx.proxy.cached_game_ids())),
    )
    return [MenuItem(strings.PROXY, status, ctx.icon("cloud"), str(waiting or ""), "proxy")]


def _about_proxy(ctx: AppContext) -> None:
    """Explain what RAOfflineProxy does, or how to turn it on.

    Args:
        ctx: App context.
    """
    text = strings.PROXY_ABOUT if ctx.proxy.enabled() else strings.PROXY_DISABLED
    message(strings.PROXY, [text])


def _change_hiding(ctx: AppContext) -> None:
    """Pick which locked descriptions are hidden.

    Args:
        ctx: App context.
    """
    current = ctx.settings.hide_descriptions.value
    chosen = pick(strings.HIDE_LOCKED, strings.HIDE_LOCKED_MODES, current)
    if chosen:
        hiding = DescriptionHiding(chosen)
        ctx.update_settings(dataclasses.replace(ctx.settings, hide_descriptions=hiding))


def _toggle(ctx: AppContext, field: str) -> None:
    """Flip a boolean setting.

    Args:
        ctx: App context.
        field: ``Settings`` field name.
    """
    current = getattr(ctx.settings, field)
    ctx.update_settings(dataclasses.replace(ctx.settings, **{field: not current}))


def _sync(ctx: AppContext, *, full: bool) -> None:
    """Start a sync (its progress shows in the bottom bar), or say one is already running.

    Args:
        ctx: App context.
        full: Start "Download every game".
    """
    if not ctx.start_sync(full=full):
        title = strings.DOWNLOAD_ALL if full else strings.SYNC_NOW
        message(title, [strings.SYNC_ALREADY_RUNNING])


def _stop_download(ctx: AppContext) -> None:
    """Stop an unfinished "Download every game" for good (downloaded games stay).

    Args:
        ctx: App context.
    """
    ctx.stop_full_download()
    message(strings.DOWNLOAD_ALL, [strings.DOWNLOAD_ALL_STOPPED])


def _clear_images(ctx: AppContext) -> None:
    """Ask for confirmation before emptying the image cache.

    Args:
        ctx: App context.
    """
    paragraphs = [strings.CLEAR_IMAGES_ASK, strings.CLEAR_IMAGES_EFFECT]
    hints = [(Button.A, strings.HINT_DELETE), (Button.B, strings.CANCEL)]
    if prompt(strings.IMAGE_CACHE, paragraphs, hints) is Button.A:
        ctx.media_cache.clear()
        message(strings.IMAGE_CACHE, [strings.IMAGES_CLEARED])


def show_settings(ctx: AppContext) -> None:
    """Show settings until B.

    Args:
        ctx: App context.
    """
    actions: dict[str, Callable[[], None]] = {
        "spoilers": lambda: _change_hiding(ctx),
        "proxy": lambda: _about_proxy(ctx),
        "auto": lambda: _toggle(ctx, "auto_sync"),
        "sync": lambda: _sync(ctx, full=False),
        "full": lambda: _sync(ctx, full=True),
        "stop": lambda: _stop_download(ctx),
        "key": lambda: change_key(ctx),
        "clear": lambda: _clear_images(ctx),
    }
    selected = 0
    while choice := choose(strings.SETTINGS, _items(ctx), selected=selected, full_status=True):
        selected = choice.index
        actions[choice.item.key]()
