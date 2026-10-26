"""What a sync is asked to do, and the marks it leaves in the cache's ``meta`` table.

Kept apart from the engine so the UI can use them without importing it: the engine (and the RA
client it pulls in) loads on the sync thread, after the first frame (.agents/device.md).
"""

from __future__ import annotations

from dataclasses import dataclass

from cheevos.core.settings import BadgeScope

LAST_SYNC_KEY = "last_sync_at"
# Set while a full re-sync is unfinished: details fetched before it are re-fetched.
FULL_SINCE_KEY = "full_resync_since"
# When RA allows requests again after asking for a long pause (wall clock, epoch seconds).
RATE_LIMITED_UNTIL_KEY = "rate_limited_until"
RATE_LIMIT_PAUSE = 60.0  # assumed pause when RA rate-limits without saying for how long


@dataclass(frozen=True, slots=True)
class SyncOptions:
    """What one sync should do.

    Attributes:
        full: Start "Download every game": fetch every game's details, resuming in later
            syncs until done.
        badge_scope: Which games' badges to download.
        recent_days: Activity window for the working set and the badge scope's "recent".
    """

    full: bool = False
    badge_scope: BadgeScope = BadgeScope.ON_DEVICE_AND_RECENT
    recent_days: int = 30
