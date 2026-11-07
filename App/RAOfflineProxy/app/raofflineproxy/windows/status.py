from __future__ import annotations

"""Status panel on the Windows main menu, like the Android app's Home screen:
the proxy, awards waiting to sync and the last sync, the caching queue and its
next batch, Smart Cache progress, and watched folders. Drawn in the space the
shared menu leaves to the right of the list; the numbers are refreshed every
couple of seconds rather than every frame. Mixed into WindowsMenuSession."""

import time

from .. import cache_budget, cache_queue, watch_folders
from . import background as windows_background
from . import history as windows_history
from ..menu_sdl import PRIMARY_COLOR, SECONDARY_TEXT_COLOR, SELECTED_COLOR, TEXT_COLOR
from ..storage import PENDING_AWARD_STATUS_PENDING, current_millis

PANEL_REFRESH_SECONDS = 2.0


def clock(millis: int) -> str:
    """HH:MM today, or the date as well when it isn't today."""
    moment = time.localtime(millis / 1000)
    if time.strftime("%Y-%m-%d", moment) == time.strftime("%Y-%m-%d"):
        return time.strftime("%H:%M", moment)
    return time.strftime("%Y-%m-%d %H:%M", moment)


class StatusPanelMixin:
    status_panel_lines: list[tuple[str, str, bool]] = []
    status_panel_at: float = 0.0

    def status_panel_rows(self) -> list[tuple[str, str, bool]]:
        """(heading, value, highlighted) per row."""
        running = self.proxy_running()
        online = bool(self.main_online)
        rows = [("Proxy", f"{'Running' if running else 'Stopped'}, {'online' if online else 'offline'}", not running)]

        pending = sum(
            1
            for award in self.storage.get_pending_awards()
            if award.get("status", PENDING_AWARD_STATUS_PENDING) == PENDING_AWARD_STATUS_PENDING
        )
        if pending:
            when = "when back online" if not online else ("on the next sync" if running else "once the proxy runs")
            rows.append(("Awards", f"{pending} waiting to sync {when}", True))
        else:
            rows.append(("Awards", "All synced", False))
        history = windows_history.list_synced_awards(self.storage)
        if history:
            rows.append(("Last synced", f"{history[0].achievement_title} ({clock(history[0].queued_at)})", False))

        queued = cache_queue.count(self.storage)
        if queued:
            if cache_queue.draining_elsewhere():
                rows.append(("Caching", f"{queued} queued, caching now", True))
            else:
                next_at = cache_budget.next_available_at(self.storage)
                batch = "soon" if next_at <= current_millis() else f"at {clock(next_at)}"
                paused = "" if running else " (paused, proxy stopped)"
                rows.append(("Caching", f"{queued} queued, next batch {batch}{paused}", True))
        else:
            rows.append(("Caching", f"{len(self.cached_games)} games cached, nothing queued", False))

        smart = windows_background.status_text()
        if smart:
            detail = smart.removeprefix("Smart Cache: ").removeprefix("Smart Cache ")
            rows.append(("Smart Cache", detail[:1].upper() + detail[1:], True))

        folders = watch_folders.watched_folders(self.config_data)
        if folders:
            scans = watch_folders.last_scans(self.storage)
            checked = [scans[f] for f in map(watch_folders.normalize_folder, folders) if scans.get(f)]
            if checked:
                rows.append(("Watched", f"{len(folders)} folder(s), last checked {clock(max(checked))}", False))
            else:
                rows.append(("Watched", f"{len(folders)} folder(s), first check after 5 idle minutes", False))
        return rows

    def render_home_logo(self) -> None:
        super().render_home_logo()
        if self.view != "main":
            return
        now = time.monotonic()
        if now - self.status_panel_at >= PANEL_REFRESH_SECONDS:
            self.status_panel_at = now
            try:
                self.status_panel_lines = self.status_panel_rows()
            except Exception:
                pass  # a status read failing shouldn't take the menu down
        self.render_status_panel()

    def render_status_panel(self) -> None:
        left = self.width // 2
        top = self.item_start_y()
        if self.logo_surface is not None:
            top = max(top, self.logo_surface.get_height() + 48)
        width = self.width - left - 32
        title = self.status_font.render("STATUS", False, PRIMARY_COLOR)
        self.surface.blit(title, (left, top))
        y = top + title.get_height() + 16
        for heading, value, highlighted in self.status_panel_lines:
            label = self.meta_font.render(heading.upper(), False, SECONDARY_TEXT_COLOR)
            self.surface.blit(label, (left, y))
            y += label.get_height() + 4
            for line in self.wrap_text_to_width(value, self.item_font, width) or [""]:
                text = self.item_font.render(line, False, SELECTED_COLOR if highlighted else TEXT_COLOR)
                self.surface.blit(text, (left, y))
                y += text.get_height() + 2
            y += 14
