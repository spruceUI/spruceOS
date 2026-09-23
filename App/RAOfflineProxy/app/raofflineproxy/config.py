from __future__ import annotations

import json
import logging
import logging.handlers
import os
from collections.abc import Callable
from pathlib import Path


DEFAULT_ONION_APP_DIR = Path("/mnt/SDCARD/App/RAOfflineProxy")
DEFAULT_ONION_STARTUP_SCRIPT = Path("/mnt/SDCARD/.tmp_update/startup/raofflineproxy.sh")
# Allium packages apps as .pak directories under Apps/, not Onion's App/ layout, but runs
# on the same Miyoo Mini firmware base (same /mnt/SDCARD/.tmp_update/updater boot chain).
DEFAULT_ALLIUM_APP_DIR = Path("/mnt/SDCARD/Apps/RAOfflineProxy.pak")
ALLIUM_MARKER_DIR = Path("/mnt/SDCARD/.allium")
# spruceOS keeps its bare version string ("4.3.3") in this file — the same one its own
# updater and spruceRestore upgrade scripts read.
SPRUCE_VERSION_FILE = Path("/mnt/SDCARD/spruce/spruce")
# Onion's own version marker, used to break a tie when both firmwares have left traces on
# the card. See running_on_spruce().
ONION_VERSION_FILE = Path("/mnt/SDCARD/.tmp_update/onionVersion/version.txt")
SPRUCE_RA_CONFIG_DIR = Path("/mnt/SDCARD/Saves/ra-configs")
# spruce keeps the RetroAchievements credentials entered in its own settings here, and
# only writes them into the RetroArch config when a game launches (its prepare_ra_config
# seds them in). Before the first launch the config's cheevos_username is still empty, so
# this file is the only place the credentials exist.
SPRUCE_CONFIG_JSON = Path("/mnt/SDCARD/Saves/spruce/spruce-config.json")
SPRUCE_SETTINGS_MENU = "RetroAchievements Settings"
CPUINFO_PATH = Path("/proc/cpuinfo")
MAGICX_MARKER = Path("/usr/magicx")
BASEOS_RELEASE_PATH = Path("/etc/baseos-release")
LOONG_DAEMON = Path("/loong/loong_daemon")
SDCARD_RETROARCH_CFG_CANDIDATES = (
    Path("/mnt/SDCARD/RetroArch/.retroarch/retroarch.cfg"),
)
DEFAULT_MUOS_APPLICATION_DIR = Path("/run/muos/storage/application/RAOfflineProxy")
DEFAULT_MUOS_INIT_DIR = Path("/run/muos/storage/init")
DEFAULT_MUOS_RETROARCH_CFG = Path("/opt/muos/share/info/config/retroarch.cfg")
MUOS_USER_INIT_CONFIG = Path("/opt/muos/config/settings/advanced/user_init")
DEFAULT_BATOCERA_CONF = Path("/userdata/system/batocera.conf")
DEFAULT_KNULLI_CONF = Path("/userdata/system/knulli.conf")
# Knulli/Batocera generate retroarchcustom.cfg at the first libretro launch, so a
# freshly flashed device has none of these yet. Keep the canonical path as the
# fallback: /userdata already established the platform, and falling
# through to the other platforms' branches would hand back a path Knulli never uses.
KNULLI_RETROARCH_CFG_CANDIDATES = (
    Path("/userdata/system/configs/retroarch/retroarchcustom.cfg"),
    Path("/userdata/system/configs/retroarch/retroarch.cfg"),
    Path("/userdata/system/.config/retroarch/retroarchcustom.cfg"),
    Path("/userdata/system/.config/retroarch/retroarch.cfg"),
)
DEFAULT_ROCKNIX_RETROARCH_CFG = Path("/storage/.config/retroarch/retroarch.cfg")
DEFAULT_ROCKNIX_CONFIG_DIR = Path("/storage/.config/raofflineproxy")
DEFAULT_ROCKNIX_PPSSPP_INI = Path("/storage/.config/ppsspp/PSP/SYSTEM/ppsspp.ini")
DEFAULT_ROCKNIX_DOLPHIN_CONFIG_DIR = Path("/storage/.config/dolphin-emu")
# ROCKNIX's setsettings.sh strips cheevos_username/cheevos_password out of retroarch.cfg
# on every game launch, so this is where the credentials the user entered actually live,
# in Batocera's key format (global.retroachievements.username/password/token).
DEFAULT_ROCKNIX_SYSTEM_CFG = Path("/storage/.config/system/configs/system.cfg")
OS_RELEASE_PATH = Path("/etc/os-release")
DEFAULT_DARKOS_HOME = Path("/home/ark")
# ArkOS-family images ship a second, 32-bit RetroArch build with its own config tree.
# EmulationStation dispatches part of the library to it (es_systems.cfg carries both
# <emulator name="retroarch"> and <emulator name="retroarch32"> entries), so it holds
# its own achievements credentials and needs its own proxy patch.
DEFAULT_DARKOS_RETROARCH32_CFG = (
    DEFAULT_DARKOS_HOME / ".config" / "retroarch32" / "retroarch.cfg"
)


def running_on_rocknix() -> bool:
    try:
        content = OS_RELEASE_PATH.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    return 'OS_NAME="ROCKNIX"' in content


def running_on_spruce() -> bool:
    if not SPRUCE_VERSION_FILE.exists():
        return False

    # Reinstalling Onion over a card that once ran spruce leaves /mnt/SDCARD/spruce in
    # place, which would otherwise make an Onion device answer yes here and then get
    # spruce's config path, port and boot hook. Onion's own version file settles it: the
    # reverse case cannot happen, because spruce's updater deletes .tmp_update wholesale.
    return not ONION_VERSION_FILE.exists()


def running_on_onion() -> bool:
    # spruceOS reuses Onion's /mnt/SDCARD/App layout, so the app directory alone does not
    # identify Onion — without the spruce exclusion every Onion-only branch (most visibly
    # the OnionOS version gate) would also fire on spruce.
    return DEFAULT_ONION_APP_DIR.exists() and not running_on_spruce()


def running_on_allium() -> bool:
    return ALLIUM_MARKER_DIR.is_dir()


def running_on_shared_miyoo_stack() -> bool:
    """Onion, spruce and Allium share the same Miyoo Mini hardware, so this app ships one
    bundled stack for all three: the "Mini" SDL2 video driver, no fontconfig, and
    gpio-keys-polled raw evdev input."""
    return running_on_onion() or running_on_spruce() or running_on_allium()


def running_on_mini_sdl_stack() -> bool:
    """The Renderer + streaming-texture display path in menu_sdl exists for the vendored
    "Mini" SDL2 video driver, not for the firmware as a whole. Onion and Allium always
    select that driver; spruce only does on MiyooMini, because its aarch64 bundle ships a
    stock SDL2 that has no such driver and would fail at Renderer creation."""
    return os.environ.get("SDL_VIDEODRIVER") == "Mini"


def running_on_darkos() -> bool:
    return DEFAULT_DARKOS_HOME.exists()


# Mirrors spruce's own device detection (spruce/scripts/helperFunctions.sh). The name has
# to match exactly: it selects Saves/ra-configs/retroarch-<name>.cfg, and spruce ships
# one config per panel and pad layout rather than one per SoC.
_SPRUCE_CPUINFO_PLATFORMS = (
    ("sun8i", "A30"),
    ("TG5040", "SmartPro"),
    ("TG3040", "Brick"),
    ("TG5050", "SmartProS"),
    ("TG4040", "BrickPro"),
    ("0xd04", "Pixel2"),
)

# BASEOS_TARGET -> spruce platform for the Allwinner H700 (0xd03) Anbernic line.
_SPRUCE_H700_PLATFORMS = {
    "rg28xx": "AnbernicRG28XX",
    "rgcubexx": "AnbernicRGCubeXX",
    "rg34xxsp": "AnbernicXX720480",
    "rg34xx": "AnbernicXX720480NoStick",
    "rgsp": "AnbernicXX720480NoStick",
    "rg35xxplus": "AnbernicXX640480NoStick",
    "rg35xxsp": "AnbernicXX640480NoStick",
    "rg40xxv": "AnbernicXX640480OneStick",
}
_SPRUCE_H700_DEFAULT = "AnbernicXX640480"


def _baseos_target() -> str:
    try:
        content = BASEOS_RELEASE_PATH.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""

    for line in content.splitlines():
        if line.startswith("BASEOS_TARGET="):
            return line.split("=", 1)[1].strip()

    return ""


def _spruce_rk3566_platform() -> str:
    """The RK3566 boards share a Cortex-A55 part id, so cpuinfo alone cannot separate
    them."""
    try:
        os_release = OS_RELEASE_PATH.read_text(encoding="utf-8", errors="replace")
    except OSError:
        os_release = ""

    if 'OS_NAME="DARKMOSS"' in os_release:
        return "RGB30"

    if LOONG_DAEMON.exists():
        return "Miniloong"

    return "Flip"


def spruce_platform() -> str:
    try:
        info = CPUINFO_PATH.read_text(encoding="utf-8", errors="replace")
    except OSError:
        info = ""

    for token, name in _SPRUCE_CPUINFO_PLATFORMS:
        if token in info:
            return name

    if "0xd05" in info:
        return _spruce_rk3566_platform()

    if "0xd03" in info:
        return _SPRUCE_H700_PLATFORMS.get(_baseos_target(), _SPRUCE_H700_DEFAULT)

    if MAGICX_MARKER.exists():
        return "Zero28"

    return "MiyooMini"


def spruce_retroarch_cfg() -> Path:
    """The live per-device config spruce launches RetroArch with. RetroArch/platform holds
    only .cfg.bak seeds since spruce 4.4.2."""
    return SPRUCE_RA_CONFIG_DIR / f"retroarch-{spruce_platform()}.cfg"


def spruce_setting(name: str) -> str | None:
    """Reads .menuOptions."<menu>".<name>.selected out of spruce's settings file, the same
    path its own get_config_value helper uses."""
    try:
        with SPRUCE_CONFIG_JSON.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return None

    if not isinstance(data, dict):
        return None

    menu = data.get("menuOptions")
    if not isinstance(menu, dict):
        return None

    section = menu.get(SPRUCE_SETTINGS_MENU)
    if not isinstance(section, dict):
        return None

    entry = section.get(name)
    if not isinstance(entry, dict):
        return None

    value = entry.get("selected")
    if not isinstance(value, str):
        return None

    return value.strip() or None


def resolve_config_dir() -> Path:
    configured = os.environ.get("RAOFFLINEPROXY_CONFIG_DIR")
    if configured:
        return Path(configured).expanduser()

    xdg_config_home = os.environ.get("XDG_CONFIG_HOME")
    if xdg_config_home:
        return Path(xdg_config_home).expanduser() / "raofflineproxy"

    if DEFAULT_ONION_APP_DIR.exists():
        return DEFAULT_ONION_APP_DIR / "data"

    if DEFAULT_ALLIUM_APP_DIR.exists():
        return DEFAULT_ALLIUM_APP_DIR / "data"

    if DEFAULT_MUOS_APPLICATION_DIR.exists():
        return DEFAULT_MUOS_APPLICATION_DIR / "data"

    if DEFAULT_DARKOS_HOME.exists():
        return DEFAULT_DARKOS_HOME / ".config" / "raofflineproxy"

    if Path("/userdata/system").exists():
        return Path("/userdata/system/.config/raofflineproxy")

    if running_on_rocknix():
        return DEFAULT_ROCKNIX_CONFIG_DIR

    return Path.home() / ".config" / "raofflineproxy"


RA_HOST = "https://retroachievements.org"
RA_MEDIA_HOST = "https://media.retroachievements.org"
APP_VERSION = os.environ.get("RAOFFLINEPROXY_APP_VERSION") or "1.13.0-alpha1"
PROXY_UA_TAG = f"RAOfflineProxy/Linux/{APP_VERSION}"
FALLBACK_USER_AGENT = "RetroArch/1.21.0 (Linux)"

DEFAULT_PROXY_PORT = 8080
# spruce ships SFTPGo bound to 0.0.0.0:8080 (its sftpgo.json httpd binding) and starts it
# whenever SFTPGo is enabled in Network Settings, so the usual default can never bind.
SPRUCE_DEFAULT_PROXY_PORT = 8099
MIN_PROXY_PORT = 1024
MAX_PROXY_PORT = 65535

CONFIG_DIR = resolve_config_dir()
CONFIG_FILE = CONFIG_DIR / "config.json"
STATE_FILE = CONFIG_DIR / "retroarch_patch_state.json"
DATABASE_FILE = CONFIG_DIR / "proxy.sqlite3"
PID_FILE = CONFIG_DIR / "service.pid"
LOG_FILE = CONFIG_DIR / "service.log"
STATUS_FILE = CONFIG_DIR / "service_status.json"
ONLINE_STATE_FILE = CONFIG_DIR / "online_state.json"
AWARD_SECRET_FILE = CONFIG_DIR / "award_secret.key"
UPDATE_STATUS_FILE = CONFIG_DIR / "update_status.json"


def ensure_config_dir() -> Path:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    return CONFIG_DIR


def configure_logging() -> None:
    ensure_config_dir()
    handler = logging.handlers.RotatingFileHandler(
        str(LOG_FILE),
        maxBytes=2 * 1024 * 1024,
        backupCount=1,
        encoding="utf-8",
    )
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
    logging.basicConfig(handlers=[handler], level=logging.INFO, force=True)


def load_config() -> dict:
    if not CONFIG_FILE.exists():
        return {}

    with CONFIG_FILE.open(encoding="utf-8") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            logging.getLogger("raofflineproxy").warning(
                "Config file %s is empty or corrupt, resetting to defaults", CONFIG_FILE
            )
            return {}

    if not isinstance(data, dict):
        raise ValueError(f"Invalid config file: {CONFIG_FILE}")

    return data


def image_caching_enabled(config_data: dict | None = None) -> bool:
    config_data = config_data or {}
    configured = config_data.get("cache_images")
    if configured is not None:
        return bool(configured)

    env_value = os.environ.get("RAOFFLINEPROXY_CACHE_IMAGES")
    if env_value is not None:
        return env_value.strip().lower() not in {"0", "false", "no", "off"}

    return True


def save_config(data: dict) -> None:
    ensure_config_dir()
    with CONFIG_FILE.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")


def default_proxy_port() -> int:
    return SPRUCE_DEFAULT_PROXY_PORT if running_on_spruce() else DEFAULT_PROXY_PORT


def proxy_port(config_data: dict) -> int:
    raw_port = config_data.get("proxy_port", default_proxy_port())
    port = int(raw_port)
    if not (MIN_PROXY_PORT <= port <= MAX_PROXY_PORT):
        raise ValueError(f"Invalid proxy port: {port}")
    return port


def proxy_host(config_data: dict) -> str:
    return str(config_data.get("proxy_host") or "127.0.0.1")


def proxy_value(config_data: dict) -> str:
    return f"{proxy_host(config_data)}:{proxy_port(config_data)}"


def proxy_base(config_data: dict) -> str:
    return f"http://{proxy_value(config_data)}"


def upstream_host(config_data: dict) -> str:
    return str(config_data.get("upstream_host") or RA_HOST).rstrip("/")


def detect_batocera_conf(config_data: dict) -> str | None:
    configured = config_data.get("batocera_conf")
    if configured:
        return str(configured)

    env_override = os.environ.get("RAOFFLINEPROXY_BATOCERA_CONF")
    if env_override:
        return env_override

    if Path("/opt/muos/script/archive").exists():
        return None

    # ROCKNIX has no batocera.conf/knulli.conf, but its system.cfg is the same thing
    # under a different name: EmulationStation writes the identical
    # global.retroachievements[.hardcore] keys there, and setsettings.sh feeds them
    # into RetroArch. Without this, hardcore stays on and every unlock the proxy
    # forwards is rejected with hardcore_not_supported.
    rocknix_system_cfg = detect_rocknix_system_cfg(config_data)
    if rocknix_system_cfg:
        return rocknix_system_cfg

    if DEFAULT_KNULLI_CONF.exists():
        return str(DEFAULT_KNULLI_CONF)

    if DEFAULT_BATOCERA_CONF.exists():
        return str(DEFAULT_BATOCERA_CONF)

    return None


def _retroarch_cfg_lookup() -> tuple[tuple[Callable[[], bool], tuple[Path, ...]], ...]:
    """Platform gate paired with that platform's cfg candidates, most specific first.

    Built per call so the module globals stay late-bound. Candidates are scoped to
    their own platform on purpose: several firmwares share a card and leave stale
    folders behind, so a single flat "first path that exists wins" list would hand
    back another firmware's config. Each platform's first candidate doubles as its
    fallback, which is what a device that has not generated its cfg yet gets.
    """
    return (
        (lambda: DEFAULT_MUOS_RETROARCH_CFG.exists(), (DEFAULT_MUOS_RETROARCH_CFG,)),
        (lambda: Path("/userdata").exists(), tuple(KNULLI_RETROARCH_CFG_CANDIDATES)),
        (
            lambda: running_on_rocknix() or Path("/storage").exists(),
            (DEFAULT_ROCKNIX_RETROARCH_CFG,),
        ),
        # Ahead of the shared /mnt/SDCARD entry: spruce lives on the same card as Onion
        # but launches RetroArch with --config pointing at a per-device file, so it never
        # reads .retroarch/retroarch.cfg. Candidates stay empty off spruce so the device
        # lookup behind spruce_retroarch_cfg() only runs where it applies.
        (
            running_on_spruce,
            (spruce_retroarch_cfg(),) if running_on_spruce() else (),
        ),
        (lambda: Path("/mnt/SDCARD").exists(), tuple(SDCARD_RETROARCH_CFG_CANDIDATES)),
    )


def detect_retroarch_cfg() -> str:
    env_override = os.environ.get("RAOFFLINEPROXY_RETROARCH_CFG")
    if env_override:
        return env_override

    for platform_matches, candidates in _retroarch_cfg_lookup():
        if not platform_matches() or not candidates:
            continue
        for candidate in candidates:
            if candidate.exists():
                return str(candidate)
        return str(candidates[0])

    return str(Path.home() / ".config" / "retroarch" / "retroarch.cfg")


def detect_rocknix_system_cfg(config_data: dict | None = None) -> str | None:
    configured = (config_data or {}).get("rocknix_system_cfg")
    if configured:
        return str(configured)

    env_override = os.environ.get("RAOFFLINEPROXY_ROCKNIX_SYSTEM_CFG")
    if env_override:
        return env_override

    if running_on_rocknix() and DEFAULT_ROCKNIX_SYSTEM_CFG.exists():
        return str(DEFAULT_ROCKNIX_SYSTEM_CFG)

    return None


def detect_darkos_retroarch32_cfg(config_data: dict | None = None) -> str | None:
    configured = (config_data or {}).get("darkos_retroarch32_cfg")
    if configured:
        return str(configured)

    env_override = os.environ.get("RAOFFLINEPROXY_DARKOS_RETROARCH32_CFG")
    if env_override:
        return env_override

    if running_on_darkos() and DEFAULT_DARKOS_RETROARCH32_CFG.exists():
        return str(DEFAULT_DARKOS_RETROARCH32_CFG)

    return None


def detect_ppsspp_ini(config_data: dict) -> str | None:
    configured = config_data.get("ppsspp_ini")
    if configured:
        return str(configured)

    env_override = os.environ.get("RAOFFLINEPROXY_PPSSPP_INI")
    if env_override:
        return env_override

    if DEFAULT_ROCKNIX_PPSSPP_INI.exists():
        return str(DEFAULT_ROCKNIX_PPSSPP_INI)

    return None


def detect_dolphin_config_dir(config_data: dict) -> str | None:
    configured = config_data.get("dolphin_config_dir")
    if configured:
        return str(configured)

    env_override = os.environ.get("RAOFFLINEPROXY_DOLPHIN_CONFIG_DIR")
    if env_override:
        return env_override

    if DEFAULT_ROCKNIX_DOLPHIN_CONFIG_DIR.exists():
        return str(DEFAULT_ROCKNIX_DOLPHIN_CONFIG_DIR)

    return None


def detect_dolphin_ini(config_data: dict) -> str | None:
    configured = config_data.get("dolphin_ini")
    if configured:
        return str(configured)

    env_override = os.environ.get("RAOFFLINEPROXY_DOLPHIN_INI")
    if env_override:
        return env_override

    config_dir = detect_dolphin_config_dir(config_data)
    if config_dir is None:
        return None

    return str(Path(config_dir) / "RetroAchievements.ini")
