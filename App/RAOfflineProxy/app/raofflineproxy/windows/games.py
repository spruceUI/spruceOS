from __future__ import annotations

"""Cached Games for the Windows menu, as the Android app shows them: grouped
under collapsible console headers, searchable, each game with its unlock count
and cache date, and its achievement list (locked ones too when that setting is
on) with descriptions and points. Mixed into WindowsMenuSession."""

import json
import logging
import time
from dataclasses import dataclass

from .. import cache_keys
from ..config import load_config, save_config
from ..rom_browser import CachedGameEntry, cached_achievements_by_id, merged_unlock_ids, remove_cached_game
from ..storage import PENDING_AWARD_STATUS_PENDING
from .settings import SHOW_LOCKED_KEY, setting_enabled

LOGGER = logging.getLogger("raofflineproxy")

CONSOLE_ACTIONS_VIEW = "win_console_actions"
CONSOLE_REMOVE_CONFIRM_VIEW = "win_console_remove_confirm"
COLLAPSED_CONSOLES_KEY = "collapsed_console_ids"

ADD_ROM = "Add ROM"
SMART_CACHE = "Start Smart Cache"
SEARCH = "Search games"
CLEAR_CACHE = "Clear cache"
BACK = "Back"
REMOVE_CACHE = "Remove cache"

# RetroAchievements console ids, the same table as the Android app's ConsoleNames.
CONSOLE_NAMES = {
    7: "NES", 81: "Famicom Disk System", 3: "SNES", 2: "Nintendo 64", 16: "GameCube",
    19: "Wii", 4: "Game Boy", 6: "Game Boy Color", 5: "Game Boy Advance", 18: "Nintendo DS",
    78: "Nintendo DSi", 24: "Pokemon Mini", 28: "Virtual Boy", 12: "PlayStation",
    21: "PlayStation 2", 41: "PlayStation Portable", 25: "Atari 2600", 51: "Atari 7800",
    17: "Atari Jaguar", 77: "Atari Jaguar CD", 13: "Atari Lynx", 33: "SG-1000",
    11: "Master System", 1: "Genesis/Mega Drive", 9: "Sega CD", 10: "32X", 39: "Saturn",
    40: "Dreamcast", 15: "Game Gear", 47: "PC-8000/8800", 8: "PC Engine/TurboGrafx-16",
    76: "PC Engine CD/TurboGrafx-CD", 49: "PC-FX", 56: "Neo Geo CD", 14: "Neo Geo Pocket",
    43: "3DO Interactive Multiplayer", 37: "Amstrad CPC", 38: "Apple II", 27: "Arcade",
    73: "Arcadia 2001", 71: "Arduboy", 44: "ColecoVision", 75: "Elektor TV Games Computer",
    57: "Fairchild Channel F", 45: "Intellivision", 74: "Interton VC 4000",
    23: "Magnavox Odyssey 2", 69: "Mega Duck", 29: "MSX", 102: "Standalone", 80: "Uzebox",
    46: "Vectrex", 72: "WASM-4", 63: "Watara Supervision", 53: "WonderSwan",
}


def console_name(console_id: int) -> str:
    return CONSOLE_NAMES.get(console_id, "Unknown")


@dataclass
class GameInfo:
    game: CachedGameEntry
    console_id: int
    total: int
    unlocked: int
    pending: int
    cached_at: int
    achievement_ids: frozenset = frozenset()

    @property
    def meta_text(self) -> str:
        date = time.strftime("%Y-%m-%d", time.localtime(self.cached_at / 1000)) if self.cached_at else "?"
        text = f"{self.unlocked} / {self.total} unlocked · cached {date}"
        if self.pending:
            text += f" · {self.pending} pending"
        return text


@dataclass
class Row:
    kind: str  # "action", "header", "game"
    label: str
    console_id: int | None = None
    info: GameInfo | None = None


def load_game_info(storage, game: CachedGameEntry, pending_ids: set[int]) -> GameInfo:
    console_id = 0
    cached_at = 0
    for entry in storage.iter_cache_by_prefix(cache_keys.patch_prefix(game.game_id)):
        cached_at = max(cached_at, int(entry.get("firstCachedAt") or entry.get("cachedAt") or 0))
        if console_id:
            continue
        try:
            console_id = int(json.loads(entry["responseBody"]).get("PatchData", {}).get("ConsoleID") or 0)
        except (ValueError, TypeError, AttributeError):
            pass
    achievements = cached_achievements_by_id(storage, game.game_id)
    unlocked = set(merged_unlock_ids(storage, game.game_id) or [])
    return GameInfo(
        game=game,
        console_id=console_id,
        total=len(achievements),
        unlocked=len(unlocked & set(achievements)),
        pending=len(pending_ids & set(achievements)),
        cached_at=cached_at,
        achievement_ids=frozenset(achievements),
    )


# Game details are loaded in the background and shown in batches of this many,
# so a big library doesn't freeze the menu.
GAME_INFO_BATCH = 25


class GamesMixin:
    game_infos: dict[int, GameInfo] | None = None
    game_infos_stale: bool = True
    game_infos_thread = None
    game_infos_missing: int = 0
    search_query: str = ""
    active_console_id: int | None = None
    displayed_achievements: list[dict] = []

    # Data -----------------------------------------------------------------------

    def refresh_cached_games(self) -> None:
        super().refresh_cached_games()
        # The shared menu calls this whenever the cache counts move (every few
        # seconds while a background queue drains), so only new games get loaded.
        self.game_infos_stale = True

    def ensure_game_infos(self) -> dict[int, GameInfo]:
        """The loaded details so far; a background thread fills in the rest.
        Only that thread builds the dict, and it publishes a fresh one each
        batch, so the menu never reads it mid-change."""
        import threading

        if self.game_infos is None:
            self.game_infos = {}
        loading = self.game_infos_thread is not None and self.game_infos_thread.is_alive()
        if self.game_infos_stale and not loading:
            self.game_infos_stale = False
            games = list(self.cached_games)
            self.game_infos_thread = threading.Thread(
                target=self.load_game_infos, args=(games, dict(self.game_infos)), daemon=True
            )
            self.game_infos_thread.start()
        return self.game_infos

    def load_game_infos(self, games: list, known: dict[int, GameInfo]) -> None:
        try:
            self._load_game_infos(games, known)
        except Exception:
            LOGGER.exception("Loading cached game details failed")
            self.game_infos_stale = True  # tried again on the next refresh
        finally:
            self.game_infos_missing = 0

    def _load_game_infos(self, games: list, known: dict[int, GameInfo]) -> None:
        pending_ids = {
            int(award.get("achievementId", 0))
            for award in self.storage.get_pending_awards()
            if award.get("status", PENDING_AWARD_STATUS_PENDING) == PENDING_AWARD_STATUS_PENDING
        }
        current = {game.game_id: game for game in games}
        infos = {game_id: info for game_id, info in known.items() if game_id in current}
        for info in infos.values():
            info.pending = len(pending_ids & info.achievement_ids)
        missing = [game for game_id, game in current.items() if game_id not in infos]
        self.game_infos_missing = len(missing)
        self.game_infos = dict(infos)
        for start in range(0, len(missing), GAME_INFO_BATCH):
            for game in missing[start:start + GAME_INFO_BATCH]:
                infos[game.game_id] = load_game_info(self.storage, game, pending_ids)
            self.game_infos = dict(infos)
            self.game_infos_missing = max(0, len(missing) - start - GAME_INFO_BATCH)

    def collapsed_consoles(self) -> set[int]:
        value = self.config_data.get(COLLAPSED_CONSOLES_KEY)
        return {int(item) for item in value} if isinstance(value, list) else set()

    def set_console_collapsed(self, console_id: int, collapsed: bool) -> None:
        self.config_data = load_config()
        current = self.collapsed_consoles()
        current = current | {console_id} if collapsed else current - {console_id}
        self.config_data[COLLAPSED_CONSOLES_KEY] = sorted(current)
        save_config(self.config_data)

    def cached_game_rows(self) -> list[Row]:
        rows: list[Row] = []
        if self.main_online:
            rows += [Row("action", ADD_ROM), Row("action", SMART_CACHE)]
        rows.append(Row("action", f"Search: {self.search_query}" if self.search_query else SEARCH))

        infos = list(self.ensure_game_infos().values())
        query = self.search_query.strip().lower()
        if query:
            infos = [info for info in infos if query in info.game.title.lower()]
        by_console: dict[int, list[GameInfo]] = {}
        for info in infos:
            by_console.setdefault(info.console_id, []).append(info)

        # Searching shows every match, so collapsed groups open up meanwhile.
        collapsed = set() if query else self.collapsed_consoles()
        for console_id in sorted(by_console, key=console_name):
            games = sorted(by_console[console_id], key=lambda info: info.game.title.lower())
            marker = "+" if console_id in collapsed else "-"
            rows.append(Row("header", f"{marker} {console_name(console_id)} ({len(games)})", console_id))
            if console_id in collapsed:
                continue
            for info in games:
                rows.append(Row("game", f"    {info.game.title}", console_id, info))

        rows += [Row("action", CLEAR_CACHE), Row("action", BACK)]
        return rows

    # Cached games screen ----------------------------------------------------------

    def cached_games_labels(self) -> list[str]:
        return [row.label for row in self.cached_game_rows()]

    def selected_row(self) -> Row | None:
        rows = self.cached_game_rows()
        return rows[self.selected_index] if 0 <= self.selected_index < len(rows) else None

    def cached_games_status(self, default: str) -> str:
        row = self.selected_row()
        if row is not None and row.kind == "game":
            return row.info.meta_text
        if self.game_infos_missing:
            return f"Loading game details: {self.game_infos_missing} left"
        return default

    def activate_cached_games_selected(self) -> None:
        row = self.selected_row()
        if row is None:
            return
        if row.kind == "game":
            self.save_view_position("cached_games")
            self.active_game = row.info.game
            self.refresh_active_game_unlocks()
            self.view = "game_actions"
            self.reset_selection()
            return
        if row.kind == "header":
            self.active_console_id = row.console_id
            self.open_view(CONSOLE_ACTIONS_VIEW)
            self.reset_selection()
            return
        if row.label == SEARCH or row.label.startswith("Search: "):
            self.open_keyboard("Search Games", "Type part of a game's title. Empty shows all.", self.set_search, initial=self.search_query)
            return
        # Add ROM, Start Smart Cache, Clear cache and Back keep their shared behaviour.
        super().activate_cached_games_selected()

    def set_search(self, text: str) -> None:
        self.search_query = text.strip()
        self.reset_selection()

    def preview_target_game(self):
        if self.view == "cached_games":
            row = self.selected_row()
            return row.info.game if row is not None and row.kind == "game" else None
        return super().preview_target_game()

    # Console actions ------------------------------------------------------------------

    def console_games(self) -> list[GameInfo]:
        return [info for info in self.ensure_game_infos().values() if info.console_id == self.active_console_id]

    def console_actions_labels(self) -> list[str]:
        collapsed = self.active_console_id in self.collapsed_consoles()
        return ["Expand" if collapsed else "Collapse", f"Remove all {len(self.console_games())} games", BACK]

    def activate_console_actions(self) -> None:
        label = self.selected_label()
        if label in ("Expand", "Collapse"):
            self.set_console_collapsed(self.active_console_id, label == "Collapse")
            self.return_to("cached_games")
        elif label.startswith("Remove all"):
            self.open_view(CONSOLE_REMOVE_CONFIRM_VIEW)
            self.reset_selection()
        else:
            self.return_to("cached_games")

    def activate_console_remove_confirm(self) -> None:
        if self.selected_label() == "YES":
            games = self.console_games()
            for info in games:
                remove_cached_game(self.storage, info.game.game_id)
            self.refresh_cached_games()
            self.flash(f"Removed {len(games)} {console_name(self.active_console_id)} games")
        self.active_console_id = None
        self.return_to("cached_games")

    # Game detail: achievements -------------------------------------------------------

    def refresh_active_game_unlocks(self) -> None:
        super().refresh_active_game_unlocks()
        if self.active_game is None:
            self.displayed_achievements = []
            return
        # Opening a game reloads its info, so unlocks earned since show up.
        if self.game_infos is not None:
            self.game_infos.pop(self.active_game.game_id, None)
            self.game_infos_stale = True
        achievements = cached_achievements_by_id(self.storage, self.active_game.game_id)
        unlocked = set(merged_unlock_ids(self.storage, self.active_game.game_id) or [])
        show_locked = setting_enabled(load_config(), SHOW_LOCKED_KEY)
        ordered = sorted(
            achievements.values(),
            key=lambda achievement: (achievement.get("ID") not in unlocked, achievement.get("DisplayOrder", 0), achievement.get("ID")),
        )
        self.displayed_achievements = [
            {**achievement, "_unlocked": achievement.get("ID") in unlocked}
            for achievement in ordered
            if show_locked or achievement.get("ID") in unlocked
        ]
        # The shared screen previews badges by title, through these.
        self.active_game_unlock_titles_cached = [a.get("Title") or "" for a in self.displayed_achievements]

    def game_actions_labels(self) -> list[str]:
        if self.active_game is not None and self.active_game_unlock_game_id != self.active_game.game_id:
            self.refresh_active_game_unlocks()
        labels = [REMOVE_CACHE]
        for achievement in self.displayed_achievements:
            mark = "[x]" if achievement["_unlocked"] else "[ ]"
            points = achievement.get("Points")
            suffix = f"  ({points} pts)" if points is not None else ""
            labels.append(f"{mark} {achievement.get('Title') or 'Achievement'}{suffix}")
        labels.append(BACK)
        return labels

    def game_actions_status(self, default: str) -> str:
        index = self.selected_index - 1
        if 0 <= index < len(self.displayed_achievements):
            description = self.displayed_achievements[index].get("Description") or ""
            return description or default
        info = self.ensure_game_infos().get(self.active_game.game_id) if self.active_game else None
        return info.meta_text if info else default
