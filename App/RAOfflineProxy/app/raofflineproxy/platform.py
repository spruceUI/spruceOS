from __future__ import annotations

from pathlib import Path

from .config import (
    DEFAULT_DARKOS_HOME,
    DEFAULT_MUOS_INIT_DIR,
    DEFAULT_ONION_STARTUP_SCRIPT,
    MUOS_USER_INIT_CONFIG,
    detect_retroarch_cfg,
    running_on_allium,
    running_on_darkos,
    running_on_rocknix,
    running_on_spruce,
    save_config,
    spruce_platform,
)
from .darkos_service import (
    DEFAULT_DARKOS_SERVICE_UNIT,
    systemd_disable_service,
    systemd_enable_service,
    systemd_remove_service,
    systemd_service_enabled,
)

DEFAULT_KNULLI_ROMS_ROOT = Path("/userdata/roms")
DEFAULT_MUOS_ROMS_ROOT = Path("/mnt/mmc/ROMS")
DEFAULT_ONION_ROMS_ROOT = Path("/mnt/SDCARD/Roms")
DEFAULT_ROCKNIX_ROMS_ROOT = Path("/storage/roms")
DEFAULT_DARKOS_ROMS_ROOT = Path("/roms")
DARKOS_SD2_ROMS_ROOT = Path("/roms2")
DARKOS_TOOLS_MOUNT = Path("/opt/system/Tools")
DEFAULT_KNULLI_STARTUP_SCRIPT = Path("/userdata/system/custom.sh")
DEFAULT_MUOS_STARTUP_SCRIPT = DEFAULT_MUOS_INIT_DIR / "raofflineproxy.sh"
DEFAULT_ROCKNIX_STARTUP_SCRIPT = Path("/storage/.config/autostart/raofflineproxy.sh")
# spruce has no drop-in boot directory: its boot entry point is one script that dispatches
# straight into the per-device startup path without returning. So the hook is inserted into
# that file, above the dispatch, rather than appended.
#
# Which file that is depends on what boots the device. Most spruce hardware comes up
# through .tmp_update/updater, but the Anbernic H700 line runs under BaseOS, which execs
# .system/h700/paks/MinUI.pak/launch.sh and reaches .tmp_update/anbernic.sh, and the RGB30
# comes up under MossySpruce via .tmp_update/rgb30.sh. Neither of those ever reads
# "updater", so a hook placed there is installed, reported as enabled, and never runs.
# One spruce card also boots all of these devices, so the hook goes into every entry point
# present rather than only the current device's (see install_spruce_boot_hook).
DEFAULT_SPRUCE_STARTUP_SCRIPT = Path("/mnt/SDCARD/.tmp_update/updater")
SPRUCE_H700_STARTUP_SCRIPT = Path("/mnt/SDCARD/.tmp_update/anbernic.sh")
SPRUCE_RGB30_STARTUP_SCRIPT = Path("/mnt/SDCARD/.tmp_update/rgb30.sh")
SPRUCE_STARTUP_SCRIPTS = (
    DEFAULT_SPRUCE_STARTUP_SCRIPT,
    SPRUCE_H700_STARTUP_SCRIPT,
    SPRUCE_RGB30_STARTUP_SCRIPT,
)
SPRUCE_AUTOSTART_LAUNCHER = Path("/mnt/SDCARD/App/RAOfflineProxy/autostart-launch.sh")
# Allium's alliumd is exec'd from the same .tmp_update/updater file spruce uses (both are
# Miyoo Mini firmwares built on the same base), so the boot hook is installed the same way.
DEFAULT_ALLIUM_STARTUP_SCRIPT = Path("/mnt/SDCARD/.tmp_update/updater")
ALLIUM_AUTOSTART_LAUNCHER = Path("/mnt/SDCARD/Apps/RAOfflineProxy.pak/autostart-launch.sh")
# The drop file Allium's own updater looks for before handing off to ota-update.sh. Our
# boot hook sits above that check, so it has to test the same path to stay out of the way.
ALLIUM_OTA_ARCHIVE = Path("/mnt/SDCARD/allium-ota.zip")
ROCKNIX_MODULES_DIR = Path("/storage/.config/modules")
ROCKNIX_MODULES_LAUNCHER = ROCKNIX_MODULES_DIR / "RAOfflineProxy.sh"
ROCKNIX_TOOL_SOURCE = Path("/storage/.local/share/raofflineproxy/RAOfflineProxy.sh")
ROM_DIRECTORY_KEYS = [
    "content_directory",
]
AUTOSTART_SENTINEL_START = "# RAOfflineProxy autostart start"
AUTOSTART_SENTINEL_END = "# RAOfflineProxy autostart end"
AUTOSTART_CONFIG_KEY = "autostart_enabled"


def resolve_retroarch_cfg(config_data: dict) -> str:
    return str(config_data.get("retroarch_cfg") or detect_retroarch_cfg())


def _same_directory(left: Path, right: Path) -> bool:
    try:
        return left.samefile(right)
    except OSError:
        return False


def darkos_roms_root() -> Path | None:
    # ArkOS's "Switch to SD2 for Roms" rebinds /opt/system/Tools from the second
    # card and rewrites every path to /roms2, but leaves /roms mounted, so its
    # existence alone does not identify the library EmulationStation is showing.
    # The Tools bind source does, and it is the same inode as the roms root it
    # came from.
    if _same_directory(DARKOS_TOOLS_MOUNT, DARKOS_SD2_ROMS_ROOT / "tools"):
        return DARKOS_SD2_ROMS_ROOT
    if DEFAULT_DARKOS_ROMS_ROOT.exists() and DEFAULT_DARKOS_ROMS_ROOT.is_dir():
        return DEFAULT_DARKOS_ROMS_ROOT
    return None


def resolve_rom_root(config_data: dict) -> Path:
    if DEFAULT_MUOS_ROMS_ROOT.exists() and DEFAULT_MUOS_ROMS_ROOT.is_dir():
        return DEFAULT_MUOS_ROMS_ROOT

    # rgui_browser_directory deliberately isn't consulted here: RetroArch
    # overwrites it with wherever its own file browser was last pointed,
    # including non-ROM folders (e.g. a themes directory), so using it as a
    # stand-in for the ROM library silently redirects the browser there.
    cfg_path = Path(resolve_retroarch_cfg(config_data))
    values = read_retroarch_cfg_values(cfg_path)
    for key in ROM_DIRECTORY_KEYS:
        value = values.get(key)
        if not value:
            continue
        candidate = Path(value).expanduser()
        if candidate.exists() and candidate.is_dir():
            return candidate

    if DEFAULT_KNULLI_ROMS_ROOT.exists() and DEFAULT_KNULLI_ROMS_ROOT.is_dir():
        return DEFAULT_KNULLI_ROMS_ROOT

    if DEFAULT_ONION_ROMS_ROOT.exists() and DEFAULT_ONION_ROMS_ROOT.is_dir():
        return DEFAULT_ONION_ROMS_ROOT

    if DEFAULT_ROCKNIX_ROMS_ROOT.exists() and DEFAULT_ROCKNIX_ROMS_ROOT.is_dir():
        return DEFAULT_ROCKNIX_ROMS_ROOT

    darkos_roms = darkos_roms_root()
    if darkos_roms is not None:
        return darkos_roms

    return cfg_path.parent


def read_retroarch_cfg_values(cfg_path: Path) -> dict[str, str]:
    if not cfg_path.exists():
        return {}

    values: dict[str, str] = {}
    for raw_line in cfg_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"')
    return values


def autostart_supported(config_data: dict) -> bool:
    return resolve_startup_script_path(config_data) is not None


def is_autostart_enabled(config_data: dict) -> bool:
    # systemd owns this on dArkOS: the unit's enabled state is the truth, not the
    # config flag, so that toggling it outside the app is still reflected here.
    if running_on_darkos():
        return systemd_service_enabled()
    if AUTOSTART_CONFIG_KEY in config_data:
        return bool(config_data[AUTOSTART_CONFIG_KEY])
    return _legacy_autostart_present(config_data)


def autostart_enabled(config_data: dict) -> bool:
    return is_autostart_enabled(config_data)


def _legacy_autostart_present(config_data: dict) -> bool:
    startup_script = resolve_startup_script_path(config_data)
    if startup_script is None or not startup_script.exists():
        return False

    if startup_script == DEFAULT_ONION_STARTUP_SCRIPT:
        return True

    if startup_script == DEFAULT_MUOS_STARTUP_SCRIPT:
        if MUOS_USER_INIT_CONFIG.exists():
            try:
                if MUOS_USER_INIT_CONFIG.read_text(encoding="utf-8").strip() != "1":
                    return False
            except OSError:
                pass
        return True

    content = startup_script.read_text(encoding="utf-8", errors="replace")
    return AUTOSTART_SENTINEL_START in content and AUTOSTART_SENTINEL_END in content


def enable_autostart(config_data: dict) -> None:
    if not autostart_supported(config_data):
        raise ValueError("Autostart is not supported on this platform")

    ensure_boot_hook(config_data)
    config_data[AUTOSTART_CONFIG_KEY] = True
    save_config(config_data)


def disable_autostart(config_data: dict) -> None:
    config_data[AUTOSTART_CONFIG_KEY] = False
    save_config(config_data)
    if running_on_darkos():
        systemd_disable_service()


def ensure_boot_hook(config_data: dict) -> None:
    startup_script = resolve_startup_script_path(config_data)
    if startup_script is None:
        raise ValueError("Autostart is not supported on this platform")

    if AUTOSTART_CONFIG_KEY not in config_data:
        config_data[AUTOSTART_CONFIG_KEY] = _legacy_autostart_present(config_data)
        save_config(config_data)

    if startup_script == DEFAULT_ONION_STARTUP_SCRIPT:
        startup_script.parent.mkdir(parents=True, exist_ok=True)
        startup_script.write_text(onion_boot_hook_script(), encoding="utf-8")
        return

    if startup_script == DEFAULT_ALLIUM_STARTUP_SCRIPT and running_on_allium():
        install_allium_boot_hook(startup_script)
        return

    if startup_script in SPRUCE_STARTUP_SCRIPTS:
        install_spruce_boot_hook(startup_script)
        return

    if startup_script == DEFAULT_MUOS_STARTUP_SCRIPT:
        startup_script.parent.mkdir(parents=True, exist_ok=True)
        startup_script.write_text(muos_boot_hook_script(config_data), encoding="utf-8")
        startup_script.chmod(0o755)
        _muos_enable_user_init()
        return

    if startup_script == DEFAULT_ROCKNIX_STARTUP_SCRIPT:
        startup_script.parent.mkdir(parents=True, exist_ok=True)
        startup_script.write_text(rocknix_boot_hook_script(config_data), encoding="utf-8")
        startup_script.chmod(0o755)
        return

    if startup_script == DEFAULT_DARKOS_SERVICE_UNIT and running_on_darkos():
        systemd_enable_service()
        return

    startup_script.parent.mkdir(parents=True, exist_ok=True)
    existing = (
        startup_script.read_text(encoding="utf-8", errors="replace")
        if startup_script.exists()
        else ""
    )
    cleaned = strip_autostart_block(existing).rstrip()
    block = autostart_block(config_data)
    new_content = f"{cleaned}\n\n{block}\n" if cleaned else f"{block}\n"
    startup_script.write_text(new_content, encoding="utf-8")


def remove_boot_hook(config_data: dict) -> None:
    startup_script = resolve_startup_script_path(config_data)
    if startup_script is None or not startup_script.exists():
        return

    if startup_script in (
        DEFAULT_ONION_STARTUP_SCRIPT,
        DEFAULT_MUOS_STARTUP_SCRIPT,
        DEFAULT_ROCKNIX_STARTUP_SCRIPT,
    ):
        startup_script.unlink()
        return

    if startup_script == DEFAULT_DARKOS_SERVICE_UNIT and running_on_darkos():
        systemd_remove_service()
        return

    if startup_script in SPRUCE_STARTUP_SCRIPTS and running_on_spruce():
        _remove_spruce_boot_hooks()
        return

    existing = startup_script.read_text(encoding="utf-8", errors="replace")
    cleaned = strip_autostart_block(existing).strip()
    startup_script.write_text(f"{cleaned}\n" if cleaned else "", encoding="utf-8")


def spruce_startup_script() -> Path:
    """spruce names the Anbernic H700 family "Anbernic*" in its own device table
    (helperFunctions.sh), so the prefix is spruce's own idiom rather than ours."""
    platform_name = spruce_platform()

    if platform_name.startswith("Anbernic"):
        return SPRUCE_H700_STARTUP_SCRIPT

    if platform_name == "RGB30":
        return SPRUCE_RGB30_STARTUP_SCRIPT

    return DEFAULT_SPRUCE_STARTUP_SCRIPT


def resolve_startup_script_path(config_data: dict) -> Path | None:
    configured = config_data.get("startup_script")
    if configured:
        return Path(str(configured))

    # Checked before spruce/Onion: Allium also ships a /mnt/SDCARD/.tmp_update of its own,
    # never sources the startup/ directory Onion uses, and packages apps as .pak
    # directories rather than spruce/Onion's shared App/ layout.
    if running_on_allium():
        return DEFAULT_ALLIUM_STARTUP_SCRIPT

    # Checked before Onion: spruce ships a /mnt/SDCARD/.tmp_update of its own, but never
    # sources the startup/ directory Onion uses, so an Onion hook there would never fire.
    if running_on_spruce():
        return spruce_startup_script()

    if Path("/mnt/SDCARD/.tmp_update").exists():
        return DEFAULT_ONION_STARTUP_SCRIPT

    if Path("/opt/muos/script/archive").exists():
        return DEFAULT_MUOS_STARTUP_SCRIPT

    if DEFAULT_DARKOS_HOME.exists():
        return DEFAULT_DARKOS_SERVICE_UNIT

    if Path("/userdata/system").exists():
        return DEFAULT_KNULLI_STARTUP_SCRIPT

    if running_on_rocknix():
        return DEFAULT_ROCKNIX_STARTUP_SCRIPT

    return None


def autostart_block(config_data: dict) -> str:
    startup_command = autostart_command(config_data)
    return "\n".join(
        [
            AUTOSTART_SENTINEL_START,
            f'if [ -x "{startup_command[0]}" ]; then',
            f"  {startup_command[0]} boot-reconcile >/dev/null 2>&1 || true",
            "fi",
            AUTOSTART_SENTINEL_END,
        ]
    )


def autostart_command(config_data: dict) -> tuple[str]:
    startup_script = resolve_startup_script_path(config_data)
    if startup_script == DEFAULT_ONION_STARTUP_SCRIPT:
        return ("/mnt/SDCARD/App/RAOfflineProxy/autostart-launch.sh",)

    if startup_script == DEFAULT_ALLIUM_STARTUP_SCRIPT and running_on_allium():
        return (str(ALLIUM_AUTOSTART_LAUNCHER),)

    if startup_script in SPRUCE_STARTUP_SCRIPTS:
        return (str(SPRUCE_AUTOSTART_LAUNCHER),)

    if startup_script == DEFAULT_MUOS_STARTUP_SCRIPT:
        return (
            str(
                config_data.get("autostart_launcher")
                or "/run/muos/storage/application/RAOfflineProxy/launch.sh"
            ),
        )

    if startup_script == DEFAULT_ROCKNIX_STARTUP_SCRIPT:
        return (
            str(
                config_data.get("autostart_launcher")
                or "/storage/.local/share/raofflineproxy/bin/raofflineproxy"
            ),
        )

    launcher = str(
        config_data.get("autostart_launcher")
        or "/userdata/system/raofflineproxy/bin/raofflineproxy"
    )
    return (launcher,)


def strip_autostart_block(content: str) -> str:
    start = content.find(AUTOSTART_SENTINEL_START)
    if start < 0:
        return content

    end = content.find(AUTOSTART_SENTINEL_END, start)
    if end < 0:
        return content[:start]

    end += len(AUTOSTART_SENTINEL_END)
    return f"{content[:start]}{content[end:]}"


def spruce_boot_hook_block() -> str:
    # Backgrounded and guarded: spruce's boot chain must never be delayed or broken by a
    # missing, slow or failing app — .tmp_update/updater is the only path to a usable
    # device, so a fault here would leave it unbootable.
    return "\n".join(
        [
            AUTOSTART_SENTINEL_START,
            f'if [ -x "{SPRUCE_AUTOSTART_LAUNCHER}" ]; then',
            f'  sh "{SPRUCE_AUTOSTART_LAUNCHER}" >/dev/null 2>&1 &',
            "fi",
            AUTOSTART_SENTINEL_END,
        ]
    )


def install_spruce_boot_hook(startup_script: Path) -> None:
    """Prepends the hook to spruce's boot entry points, straight after the shebang.

    It cannot be appended: each file ends by dispatching into a per-device startup script
    that never returns. Prepending also keeps this independent of what that dispatch looks
    like — the hook only backgrounds our launcher and needs nothing spruce sets up first.

    The device's own entry point is required. Every other spruce entry point present on
    the card gets the hook too, because one spruce card boots many devices: a card moved
    from a Miyoo Mini to an RG40XX boots through anbernic.sh instead of updater, and a hook
    in only one of them leaves autostart dead on the other. Each file only ever runs on its
    own device family, and the block is guarded and backgrounded, so the copies a device
    never executes are inert.
    """
    if not startup_script.exists():
        raise ValueError(f"spruce boot script not found: {startup_script}")

    _prepend_spruce_boot_hook(startup_script)

    for sibling in SPRUCE_STARTUP_SCRIPTS:
        if sibling == startup_script or not sibling.exists():
            continue

        try:
            _prepend_spruce_boot_hook(sibling)
        except (OSError, ValueError):
            continue


def _prepend_spruce_boot_hook(script: Path) -> None:
    existing = script.read_text(encoding="utf-8", errors="replace")
    if not existing.startswith("#!"):
        # Refuse rather than write into something that isn't the shell script we expect.
        raise ValueError(f"unrecognised spruce boot script, autostart not installed: {script}")

    cleaned = strip_autostart_block(existing)
    shebang, _, remainder = cleaned.partition("\n")
    # lstrip so repeated installs (every app launch) don't accumulate blank lines where
    # strip_autostart_block removed the previous copy.
    updated = f"{shebang}\n\n{spruce_boot_hook_block()}\n\n{remainder.lstrip(chr(10))}"
    if updated != existing:
        script.write_text(updated, encoding="utf-8")


def _remove_spruce_boot_hooks() -> None:
    for script in SPRUCE_STARTUP_SCRIPTS:
        if not script.exists():
            continue

        try:
            existing = script.read_text(encoding="utf-8", errors="replace")
            cleaned = strip_autostart_block(existing)
            if cleaned != existing:
                script.write_text(cleaned.replace("\n\n\n", "\n\n"), encoding="utf-8")
        except OSError:
            continue


def allium_boot_hook_block() -> str:
    # Same reasoning as spruce_boot_hook_block(): .tmp_update/updater is the only path to a
    # usable device on this firmware, so the hook is backgrounded and guarded.
    #
    # The pending-OTA guard matters because this block sits above the updater's own OTA
    # check: on an update boot, ota-update.sh extracts the release over the whole card and
    # then reboots, so without the guard the service would be opening its SQLite database
    # on that card mid-extract and seconds before a forced reboot.
    return "\n".join(
        [
            AUTOSTART_SENTINEL_START,
            f'if [ ! -f "{ALLIUM_OTA_ARCHIVE}" ] && [ -x "{ALLIUM_AUTOSTART_LAUNCHER}" ]; then',
            f'  sh "{ALLIUM_AUTOSTART_LAUNCHER}" >/dev/null 2>&1 &',
            "fi",
            AUTOSTART_SENTINEL_END,
        ]
    )


def install_allium_boot_hook(startup_script: Path) -> None:
    """Prepends the hook to Allium's boot entry point, straight after the shebang.

    Same file and mechanism as spruce's install_spruce_boot_hook(): the script ends by
    exec'ing alliumd, which never returns, so appending would leave the hook dead code.
    """
    if not startup_script.exists():
        raise ValueError(f"allium boot script not found: {startup_script}")

    existing = startup_script.read_text(encoding="utf-8", errors="replace")
    if not existing.startswith("#!"):
        raise ValueError(
            f"unrecognised allium boot script, autostart not installed: {startup_script}"
        )

    cleaned = strip_autostart_block(existing)
    shebang, _, remainder = cleaned.partition("\n")
    updated = f"{shebang}\n\n{allium_boot_hook_block()}\n\n{remainder.lstrip(chr(10))}"
    if updated != existing:
        startup_script.write_text(updated, encoding="utf-8")


def onion_boot_hook_script() -> str:
    return "\n".join(
        [
            "#!/bin/sh",
            "set -eu",
            "",
            "APP_DIR=/mnt/SDCARD/App/RAOfflineProxy",
            'if [ -x "$APP_DIR/autostart-launch.sh" ]; then',
            '  sh "$APP_DIR/autostart-launch.sh"',
            "fi",
            "",
        ]
    )


def _muos_enable_user_init() -> None:
    if MUOS_USER_INIT_CONFIG.parent.exists():
        MUOS_USER_INIT_CONFIG.write_text("1\n", encoding="utf-8")


def muos_boot_hook_script(config_data: dict) -> str:
    launcher = autostart_command(config_data)[0]
    return "\n".join(
        [
            "#!/bin/sh",
            "set -eu",
            "",
            f'if [ -x "{launcher}" ]; then',
            f'  exec "{launcher}" boot-reconcile >/dev/null 2>&1 || true',
            "fi",
            "",
        ]
    )


def rocknix_boot_hook_script(config_data: dict) -> str:
    launcher = autostart_command(config_data)[0]
    return "\n".join(
        [
            "#!/bin/sh",
            "set -u",
            "",
            "# ROCKNIX re-syncs /storage/.config/modules from a read-only source on",
            "# every boot (rsync --delete), wiping third-party Tools entries. Re-add",
            "# ours so the RAOfflineProxy Tools entry survives reboots.",
            f'if [ -f "{ROCKNIX_TOOL_SOURCE}" ]; then',
            f'  mkdir -p "{ROCKNIX_MODULES_DIR}"',
            f'  cp "{ROCKNIX_TOOL_SOURCE}" "{ROCKNIX_MODULES_LAUNCHER}" || true',
            f'  chmod +x "{ROCKNIX_MODULES_LAUNCHER}" || true',
            "fi",
            "",
            f'if [ -x "{launcher}" ]; then',
            f'  "{launcher}" boot-reconcile >/dev/null 2>&1 || true',
            "fi",
            "",
        ]
    )
