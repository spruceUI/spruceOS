from __future__ import annotations

import json
import time
from dataclasses import dataclass

from . import cache_keys
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
    patch_index = build_patch_index(storage)
    entries: list[PendingAwardEntry] = []
    for award in storage.get_pending_awards():
        if (
            award.get("status", PENDING_AWARD_STATUS_PENDING)
            != PENDING_AWARD_STATUS_PENDING
        ):
            continue

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


def build_patch_index(storage: Storage) -> dict[int, dict]:
    index: dict[int, dict] = {}

    for entry in storage.get_all_cache_by_prefix(cache_keys.PREFIX_PATCH):
        game_id = cache_keys.parse_game_id_from_patch_key(entry["cacheKey"])
        if game_id is None:
            continue
        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            continue

        patch_data = payload.get("PatchData") or {}
        game_title = patch_data.get("Title") or f"Game {game_id}"
        for achievement in patch_data.get("Achievements", []):
            achievement_id = achievement.get("ID")
            if not isinstance(achievement_id, int):
                continue
            index[achievement_id] = {
                "game_id": game_id,
                "game_title": game_title,
                "achievement_title": achievement.get("Title")
                or f"Achievement {achievement_id}",
                "points": achievement.get("Points"),
            }

    for entry in storage.get_all_cache_by_prefix(cache_keys.PREFIX_ACHIEVEMENTSETS):
        try:
            payload = json.loads(entry["responseBody"])
        except Exception:
            continue

        game_id = payload.get("GameId")
        if not isinstance(game_id, int) or game_id <= 0:
            continue

        game_title = payload.get("Title") or f"Game {game_id}"
        direct = payload.get("Achievements")
        if isinstance(direct, dict):
            achievement_iter = direct.values()
        elif isinstance(direct, list):
            achievement_iter = direct
        else:
            achievement_iter = (
                a
                for s in (payload.get("Sets") or [])
                if isinstance(s, dict)
                for a in (s.get("Achievements") or [])
                if isinstance(a, dict)
            )
        for achievement in achievement_iter:
            if not isinstance(achievement, dict):
                continue
            achievement_id = achievement.get("ID")
            if not isinstance(achievement_id, int):
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

    return index
