from __future__ import annotations

import json
import time
from dataclasses import dataclass

from . import cache_keys
from .rom_cache import achievement_id_pattern, likely_first_prefixes
from .storage import PENDING_AWARD_STATUS_DELETED, PENDING_AWARD_STATUS_PENDING, Storage
from .utils import extract_form_param


@dataclass
class PendingAwardEntry:
    achievement_id: int
    game_id: int | None
    game_title: str
    achievement_title: str
    points: int | None
    queued_at: int

    @property
    def date_text(self) -> str:
        return time.strftime("%Y-%m-%d %H:%M", time.localtime(self.queued_at / 1000))

    @property
    def summary_text(self) -> str:
        return f"{self.game_title} | {self.achievement_title} | {self.date_text}"

    @property
    def detail_text(self) -> str:
        detail = f"{self.achievement_title} | {self.date_text}"
        if self.points is None:
            return detail
        return f"{detail} | {self.points}pts."


def list_pending_awards(storage: Storage) -> list[PendingAwardEntry]:
    pending_awards = [
        award
        for award in storage.get_pending_awards()
        if award.get("status", PENDING_AWARD_STATUS_PENDING) == PENDING_AWARD_STATUS_PENDING
    ]
    patch_index = build_patch_index(
        storage, {int(award.get("achievementId", 0)) for award in pending_awards}
    )
    entries: list[PendingAwardEntry] = []
    for award in pending_awards:
        achievement_id = int(award.get("achievementId", 0))
        patch_info = patch_index.get(achievement_id, {})
        entries.append(
            PendingAwardEntry(
                achievement_id=achievement_id,
                game_id=patch_info.get("game_id"),
                game_title=patch_info.get("game_title") or "Unknown Game",
                achievement_title=patch_info.get("achievement_title")
                or f"Achievement {achievement_id}",
                points=patch_info.get("points"),
                queued_at=int(award.get("queuedAt", 0)),
            )
        )
    return entries


def delete_pending_award(storage: Storage, achievement_id: int) -> None:
    for award in storage.get_pending_awards():
        if int(award.get("achievementId", 0)) != achievement_id:
            continue

        award["status"] = PENDING_AWARD_STATUS_DELETED
        storage.update_pending_award(award)
        return


def build_patch_index(storage: Storage, achievement_ids: set[int]) -> dict[int, dict]:
    index: dict[int, dict] = {}
    wanted = {achievement_id for achievement_id in achievement_ids if achievement_id > 0}
    if not wanted:
        return index
    mentions_wanted = achievement_id_pattern(wanted)

    for prefix in likely_first_prefixes(storage):
        for entry in storage.iter_cache_by_prefix(prefix):
            if not mentions_wanted.search(entry["responseBody"]):
                continue
            if prefix == cache_keys.PREFIX_ACHIEVEMENTSETS:
                titled = achievementsets_titled_achievements(entry)
            else:
                titled = patch_titled_achievements(entry)
            for game_id, game_title, achievement in titled:
                achievement_id = achievement.get("ID")
                if achievement_id not in wanted:
                    continue
                index.setdefault(
                    achievement_id,
                    {
                        "game_id": game_id,
                        "game_title": game_title,
                        "achievement_title": achievement.get("Title")
                        or f"Achievement {achievement_id}",
                        "points": achievement.get("Points"),
                    },
                )
            if wanted.issubset(index):
                return index

    return index


def patch_titled_achievements(entry: dict) -> list[tuple[int, str, dict]]:
    game_id = cache_keys.parse_game_id_from_patch_key(entry["cacheKey"])
    if game_id is None:
        return []
    try:
        patch_data = json.loads(entry["responseBody"]).get("PatchData") or {}
    except Exception:
        return []
    game_title = patch_data.get("Title") or f"Game {game_id}"
    return [
        (game_id, game_title, achievement)
        for achievement in patch_data.get("Achievements", [])
        if isinstance(achievement, dict)
    ]


def achievementsets_titled_achievements(entry: dict) -> list[tuple[int, str, dict]]:
    try:
        payload = json.loads(entry["responseBody"])
    except Exception:
        return []

    game_id = payload.get("GameId")
    if not isinstance(game_id, int) or game_id <= 0:
        return []

    game_title = payload.get("Title") or f"Game {game_id}"
    direct = payload.get("Achievements")
    if isinstance(direct, dict):
        achievements = direct.values()
    elif isinstance(direct, list):
        achievements = direct
    else:
        achievements = (
            achievement
            for achievement_set in (payload.get("Sets") or [])
            if isinstance(achievement_set, dict)
            for achievement in (achievement_set.get("Achievements") or [])
        )
    return [
        (game_id, game_title, achievement)
        for achievement in achievements
        if isinstance(achievement, dict)
    ]
