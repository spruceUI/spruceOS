"""Every user-facing string, in one place (ready to map onto PyUI's ``Language`` later).

Templates use ``str.format`` named fields.
"""

from __future__ import annotations

APP_TITLE = "Cheevos"

# --- sync status (bottom bar) -----------------------------------------------------------------
SYNC = "Sync"
SYNC_CANCEL = "Cancel"
SYNC_RETRY = "Retry"
ENTER_KEY = "Enter key"  # Start after RA rejected the key; A on the setup screen
SYNC_RUNNING_ITEM = "Games {done}/{total}"
SYNC_RUNNING_RECENT = "Recent unlocks · {done} found"
SYNC_RUNNING_IMAGES = "Downloading images {done}/{total}"
SYNC_PHASES = {
    "preflight": "Checking connection",
    "profile": "Syncing profile",
    "library": "Syncing game list",
    "details": "Syncing achievements",
    "awards": "Syncing awards",
    "recent": "Syncing recent unlocks",
    "media": "Downloading images",
}
SYNC_CANCELLING = "Cancelling…"
SYNC_DONE_AGO = "Synced {ago}"
SYNC_NEVER = "Not synced yet"
SYNC_OFFLINE = "Offline · showing saved data"
SYNC_AUTH = "API key rejected"
SYNC_UNAVAILABLE = "RetroAchievements unavailable"
SYNC_RATE_LIMITED = "RetroAchievements asked to wait {minutes} min"
SYNC_CANCELLED = "Sync cancelled"
SYNC_ERROR = "Sync failed · see the log"

# --- home -------------------------------------------------------------------------------------
PROFILE_POINTS = "{hardcore} HC · {softcore} casual · {retro} RetroPoints"
UNRANKED = "Unranked"
RANK = "#{rank}"
WAITING_FOR_SYNC = "Waiting for the first sync"
GAMES = "Games"
GAMES_SUMMARY = "{count} games · {finished} mastered or beaten"
RECENT = "Recent unlocks"
NOTHING_UNLOCKED = "Nothing unlocked yet"
AWARDS = "Awards"
AWARDS_SUMMARY = "{mastered} mastered · {beaten} beaten"
SETTINGS = "Settings"
SETTINGS_SUMMARY = "Badges, sync, API key, about"

# --- games ------------------------------------------------------------------------------------
NOT_STARTED = "not started"
LAST_ACTIVITY = "{console} · {ago}"
GAME_NEVER_PLAYED = "{console} · {status}"
PERCENT = "{percent}%"
COUNT_PENDING = "{earned}+{pending}/{total}"  # +N: unlocked offline, waiting to sync
NOT_SYNCED = "{detail} · {count} not synced"
HINT_DETAILS = "Details"
HINT_FILTER = "Filter"
HINT_PROGRESS = "Progress"
AWARD_LABELS = {
    "mastered": "Mastered",
    "completed": "Completed",
    "beaten-hardcore": "Beaten",
    "beaten-softcore": "Beaten (casual)",
}
FILTER = "Filter: {value}"
SORT = "Sort: {value}"
VIEW = "View: {value}"
GAME_FILTERS = {
    "all": "All games",
    "device": "On this device",
    "progress": "In progress",
    "finished": "Mastered or beaten",
    "unstarted": "Not started",
}
GAME_SORTS = {
    "recent": "Recent activity",
    "title": "Title",
    "console": "Console",
    "completion": "Completion",
}
NO_GAMES = "No games match this filter."
NO_DETAILS = "This game's achievements aren't downloaded yet."
NO_DETAILS_HINT = "To have every game's achievements offline: Settings → Download every game."
LOADING_ACHIEVEMENTS = "Loading achievements…"
LOAD_NETWORK = "Couldn't reach RetroAchievements · check the Wi-Fi."
LOAD_ERROR = "Loading failed · see the log."

# --- achievements -----------------------------------------------------------------------------
TYPE_LABELS = {"progression": "Progression", "win_condition": "Win", "missable": "Missable"}
UNLOCKED_HARDCORE = "Hardcore {when}"
UNLOCKED_CASUAL = "Casual {when}"
PENDING = "Pending sync {when}"
RARITY = "{percent} of players"
HAS_SCREENSHOT = "screenshot"
ACH_FILTERS = {
    "all": "All",
    "locked": "Locked",
    "unlocked": "Unlocked",
    "missable": "Missable",
    "key": "Progression and win",
}
ACH_SORTS = {
    "order": "Default order",
    "unlocked": "Unlocked first",
    "locked": "Locked first",
    "points": "Points",
    "rarity": "Rarest first",
}
VIEWS = {"list": "List", "grid": "Grid"}
HINT_GRID = "Grid"
HINT_LIST = "List"
NO_ACHIEVEMENTS = "No achievements match this filter."
DETAIL_META = "{points} · {retro} RetroPoints"
DETAIL_UNLOCKED = "Unlocked ({mode}) {when}"
DETAIL_PENDING = "Unlocked offline · waiting to sync since {when}"
DETAIL_LOCKED = "Locked"
DETAIL_RARITY = "Unlocked by {casual} of players ({hardcore} in hardcore)"
HIDDEN_DESCRIPTION = "Description hidden"
HINT_REVEAL = "Reveal"
HINT_FULL_SCREEN = "Full screen"
MODE_HARDCORE = "Hardcore"
MODE_CASUAL = "Casual"

# --- profile / awards / offline ---------------------------------------------------------------
PROFILE = "Profile"
MEMBER_SINCE = "Member since {date}"
STAT_HARDCORE = "Hardcore points"
STAT_CASUAL = "Casual points"
STAT_RETRO = "RetroPoints"
STAT_RATIO = "RetroRatio"
STAT_UNLOCKS = "Achievements unlocked"
STAT_UNLOCKS_VALUE = "{hardcore} HC · {casual} casual"
STAT_BEATEN = "Games beaten"
STAT_BEATEN_VALUE = "{count} ({retail} retail)"
STAT_STARTED_BEATEN = "Started games beaten"
STAT_WEEK = "Points, last 7 days"
STAT_MONTH = "Points, last 30 days"
STAT_PER_WEEK = "Average points per week"
STAT_COMPLETION = "Average completion"
UNKNOWN = "—"
RANK_OF = "#{rank} of {total}"
RANK_TOP = "#{rank} of {total} · top {percent}"
LAST_ACTIVE = "Last active {ago}"
SECTION_PLAYING = "Last played"
SECTION_STATS = "Player stats"
SECTION_CONSOLES = "Games by console"
CONSOLE = "Console"
PLAYED = "Played"
BEATEN = "Beaten"
MASTERED = "Mastered"
ALL_CONSOLES = "All consoles"
MORE_CONSOLE = "and 1 more console"
MORE_CONSOLES = "and {count} more consoles"
MONTH_EMPTY = "No unlocks in the last 30 days"
MONTH_START = "30 days ago"
MONTH_END = "Today"
HINT_SEE_MORE = "See more"
NO_AWARDS = "No mastered or beaten games yet. Keep playing!"
NO_AWARDS_MATCH = "No awards match this filter."
AWARDS_TITLE = "Awards · {count}"
AWARD_FILTERS = {
    "all": "All awards",
    "mastery": "Mastered and completed",
    "beaten": "Beaten",
}
AWARD_SORTS = {
    "newest": "Newest first",
    "site": "Site order",
    "title": "Title",
    "console": "Console",
}
PROXY = "RAOfflineProxy"
PROXY_OFF = "Off · unlocks need Wi-Fi"
PROXY_DISABLED = (
    "RAOfflineProxy is off. Turn it on in Spruce Settings > RetroAchievements to earn "
    "achievements without Wi-Fi (Casual mode only)."
)
PROXY_ABOUT = (
    "RAOfflineProxy keeps unlocks earned without Wi-Fi and sends them to RetroAchievements when "
    'you\'re back online (Casual mode only). Until then they show as "Pending sync" in Recent '
    "unlocks and in each game, and count towards the games list."
)
PROXY_STATUS = "On · {state} · {waiting} waiting · {cached} games cached"
PROXY_ONLINE = "online"
PROXY_OFFLINE = "offline"
PROXY_UNKNOWN = "status unknown"

# --- settings ---------------------------------------------------------------------------------
BADGE_DOWNLOADS = "Badge downloads"
BADGE_SCOPES = {
    "on-device-and-recent": "On-device and recent games",
    "all": "All games",
    "none": "Only while browsing",
}
RECENT_WINDOW = "Recent games"
RECENT_DAYS = "Played in the last {days} days"
HIDE_LOCKED = "Hide locked descriptions"
HIDE_LOCKED_MODES = {"off": "Off", "story": "Story only", "all": "All"}
HIDE_LOCKED_HINTS = {
    "off": "Every description is shown",
    "story": "Progression and win achievements (if the set tags them)",
    "all": "Every locked achievement",
}
AUTO_SYNC = "Sync when the app opens"
ON = "On"
OFF = "Off"
SYNC_NOW = "Sync now"
SYNC_NOW_HINT = "Fetch what changed since the last sync"
DOWNLOAD_ALL = "Download every game"
DOWNLOAD_ALL_HINT = "For offline use · about a second per game"
DOWNLOAD_ALL_STOP = "Stop downloading every game"
DOWNLOAD_ALL_STOP_HINT = "Keep what's downloaded so far"
DOWNLOAD_ALL_STOPPED = "Stopped. What's downloaded so far stays."
SYNC_ALREADY_RUNNING = "A sync is already running"
API_KEY = "Web API key"
API_KEY_SET = "Set (ends with {tail})"
CLEAR_IMAGES = "Clear image cache"
CLEAR_IMAGES_SIZE = "{size} used · images download again when needed"
IMAGES_CLEARED = "Image cache cleared."
ABOUT = "About"
ABOUT_HINT = "Version, license and credits"
ABOUT_TEXT = (
    "Cheevos {version} · RetroAchievements hub for SpruceOS",
    "MIT License · Copyright (c) 2026 Andrii Balakhtar",
    "Data, badges and game icons: RetroAchievements.org (not affiliated)",
    "Screens drawn with PyUI · Copyright (c) 2025 Christopher Jacobs, used under its license",
)

# --- setup ------------------------------------------------------------------------------------
SETUP = "Set up Cheevos"
NO_USERNAME = (
    "Sign in to RetroAchievements first: Spruce Settings > RetroAchievements, or in "
    "RetroArch. Then open Cheevos again."
)
KEY_NEEDED = "Cheevos needs your RetroAchievements Web API key."
KEY_FILE_INVALID = "{path} doesn't hold a Web API key."
KEY_WHERE = "Find it at retroachievements.org > Settings > Keys (32 letters and digits)."
KEY_HOW = (
    "Press A to type it. Or press B to exit, save the key in {path} on the SD card, and open "
    "Cheevos again."
)
KEY_PROMPT = "RetroAchievements Web API key"
KEY_INVALID_FORMAT = "That doesn't look like a Web API key (32 letters and digits)."
KEY_CHECKING = "Checking the key with RetroAchievements…"
KEY_REJECTED = "RetroAchievements rejected this key. Check it and try again."
KEY_UNVERIFIED = "Couldn't reach RetroAchievements; the key is saved and will be checked later."
# On-screen keyboard hints (A types the highlighted key)
HINT_DONE = "Done"
HINT_DELETE = "Delete"
HINT_SHIFT = "Shift"
HINT_CAPS = "Caps"
EXIT = "Exit"

# --- generic ----------------------------------------------------------------------------------
LOADING = "Loading…"
HINT_OK = "OK"
JUST_NOW = "just now"
MINUTES_AGO = "{count} min ago"
HOURS_AGO = "{count} h ago"
YESTERDAY = "yesterday"
DAYS_AGO = "{count} days ago"
POINT = "{count} pt"
POINTS = "{count} pts"
