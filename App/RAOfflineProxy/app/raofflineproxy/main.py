from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from pathlib import Path

from .auth import resolve_credentials
from .config import (
    CONFIG_FILE,
    DEFAULT_ONION_APP_DIR,
    configure_logging,
    detect_retroarch_cfg,
    load_config,
    proxy_value,
    running_on_darkos,
    running_on_onion,
)
from .darkos_service import systemd_install_service
from .log_uploader import onion_os_version, onion_version_supported
from .platform import (
    disable_autostart,
    enable_autostart,
    ensure_boot_hook,
    is_autostart_enabled,
    remove_boot_hook,
    resolve_rom_root,
)
from .es_export import CACHED_IDS_FILE, export_cached_game_ids
from .batocera_conf import (
    patch_batocera_conf,
    revert_batocera_conf,
    store_batocera_previous,
)
from .ppsspp_cfg import (
    patch_ppsspp_ini,
    revert_ppsspp_ini,
    store_ppsspp_previous,
)
from .dolphin_cfg import (
    patch_dolphin_ini,
    revert_dolphin_ini,
    store_dolphin_previous,
)
from .retroarch_cfg import (
    enforce_patched_cfg,
    enforce_secondary_retroarch_cfgs,
    patch_retroarch_cfg,
    patch_secondary_retroarch_cfgs,
    revert_retroarch_cfg,
    revert_secondary_retroarch_cfgs,
    store_secondary_retroarch_previous,
    status_retroarch_cfg,
)
from .service import (
    run_service_foreground,
    service_status,
    start_service_process,
    stop_service_process,
)
from .menu_sdl import run_menu_sdl
from .network import apply_scan_batch_cooldown, online_check
from .pending_awards import list_pending_awards
from .rom_browser import (
    add_rom_to_cache,
    cached_unlock_count,
    cached_unlock_counts,
    cached_unlock_titles,
    clear_cached_games,
    describe_browser_entries,
    describe_browser_entries_fast,
    list_cached_games,
    load_cached_rom_paths,
    normalize_cached_rom_path,
    remove_cached_game,
)
from .smart_cache import (
    SMART_CACHE_LIMIT,
    load_content_history_paths,
    run_folder_cache,
    run_smart_cache,
    should_offer_smart_cache,
)
from .storage import Storage
from .state import load_online_state, load_patch_state, save_patch_state, save_online_state
from .ui import write_status_image, write_text_image
from .update import (
    download_onion_update_archive,
    install_onion_update_archive,
    update_status,
)

STALE_HOOK_PATH = Path("/userdata/system/scripts/RAOfflineProxy_game_hook.sh")
LOGGER = logging.getLogger("raofflineproxy")


def should_abort_from_env() -> bool:
    abort_file = os.environ.get("RAOFFLINEPROXY_ABORT_FILE")
    return bool(abort_file) and Path(abort_file).exists()


def remove_stale_hook() -> None:
    if STALE_HOOK_PATH.exists():
        STALE_HOOK_PATH.unlink()


def _patch_emulator_configs(config_data: dict, cfg_path: str) -> list[str]:
    """Point every supported emulator at the proxy. Does not touch the service.

    Split out of `_apply_proxy` so the boot path can patch without starting the
    service: on dArkOS systemd owns the process, and the unit patches from
    `ExecStartPre` rather than going through `_apply_proxy` (which would recurse
    back into `systemctl start`).
    """
    output: list[str] = []

    remove_stale_hook()
    # Read before the first patch: save_patch_state() rewrites the whole file, so
    # patch_retroarch_cfg() below drops every key it does not own.
    previous_secondary = (load_patch_state() or {}).get("secondary_cfgs", [])
    result = patch_retroarch_cfg(cfg_path, config_data)
    enforce_patched_cfg(cfg_path, config_data)
    secondary = patch_secondary_retroarch_cfgs(config_data, previous_secondary)
    enforce_secondary_retroarch_cfgs(config_data)
    batocera = patch_batocera_conf(config_data)
    ppsspp = patch_ppsspp_ini(config_data)
    dolphin = patch_dolphin_ini(config_data)
    patch_state = load_patch_state() or {}
    store_secondary_retroarch_previous(patch_state, secondary)
    store_batocera_previous(patch_state, batocera)
    store_ppsspp_previous(patch_state, ppsspp)
    store_dolphin_previous(patch_state, dolphin)
    save_patch_state(patch_state)

    if not result.get("exists", True):
        output.append(f"Skipped missing retroarch.cfg at {result['cfg_path']}")
    elif result["already_patched"]:
        output.append("retroarch.cfg already patched")
    elif result["changed"]:
        output.append("Patched retroarch.cfg")
    else:
        output.append("retroarch.cfg already patched")

    if batocera.get("exists"):
        output.append(f"Patched batocera.conf at {batocera['path']}")

    for entry in secondary.get("entries", []):
        if entry.get("changed"):
            output.append(f"Patched retroarch.cfg at {entry['cfg_path']}")

    if ppsspp.get("exists"):
        output.append(f"Patched ppsspp.ini at {ppsspp['path']}")

    if dolphin.get("exists"):
        output.append(f"Patched RetroAchievements.ini at {dolphin['path']}")

    return output


def _apply_proxy(config_data: dict, cfg_path: str) -> list[str]:
    if running_on_onion() and not onion_version_supported():
        detected = onion_os_version() or "unknown"
        raise RuntimeError(
            f"Unsupported OnionOS build ({detected}). RAOfflineProxy requires Onion "
            "v4.4.0-beta-20260120 or newer."
        )

    output: list[str] = []

    # Spawn the service first so its interpreter starts up (and binds the proxy
    # port) while the config patching below runs. At boot on devices that resume
    # content automatically, the emulator's achievement login can arrive within
    # seconds of this hook being scheduled.
    service = start_service_process(config_data)
    output.extend(_patch_emulator_configs(config_data, cfg_path))

    if service["already_running"]:
        output.append(f"Service already running (pid {service['pid']})")
    else:
        output.append(f"Service started (pid {service['pid']})")

    return output


def _revert_proxy_config(config_data: dict, cfg_path: str | None) -> list[str]:
    output: list[str] = []

    remove_stale_hook()
    patch_state = load_patch_state() or {}
    revert_cfg_path = patch_state.get("cfg_path") or cfg_path
    batocera = revert_batocera_conf(config_data, patch_state.get("batocera_previous", {}))
    ppsspp = revert_ppsspp_ini(config_data, patch_state.get("ppsspp_previous", {}))
    dolphin = revert_dolphin_ini(config_data, patch_state.get("dolphin_previous", {}))
    secondary = revert_secondary_retroarch_cfgs(
        config_data, patch_state.get("secondary_cfgs", [])
    )

    if batocera.get("exists"):
        output.append(f"Reverted batocera.conf at {batocera['path']}")

    for cfg in secondary.get("reverted", []):
        output.append(f"Reverted retroarch.cfg at {cfg}")

    if ppsspp.get("exists"):
        output.append(f"Reverted ppsspp.ini at {ppsspp['path']}")

    if dolphin.get("exists"):
        output.append(f"Reverted RetroAchievements.ini at {dolphin['path']}")

    revert_result = None
    if patch_state:
        revert_result = revert_retroarch_cfg(
            revert_cfg_path, patch_state, config_data=config_data
        )
    elif revert_cfg_path:
        try:
            revert_result = revert_retroarch_cfg(
                revert_cfg_path, config_data=config_data
            )
        except Exception:
            revert_result = None

    if revert_result is None or not revert_result.get("exists", True):
        output.append("retroarch.cfg already reverted")
    elif revert_result["changed"]:
        output.append("Reverted retroarch.cfg")
    else:
        output.append("retroarch.cfg already reverted")

    return output


def safe_stop_proxy(config_data: dict, cfg_path: str | None) -> list[str]:
    service = stop_service_process()

    if service.get("already_stopped"):
        service_line = "Service already stopped"
    elif service.get("forced"):
        service_line = f"Service stopped forcefully (pid {service['pid']})"
    else:
        service_line = f"Service stopped (pid {service['pid']})"

    return [service_line, *_revert_proxy_config(config_data, cfg_path)]


def main() -> None:
    parser = argparse.ArgumentParser(description="RAOfflineProxy Linux client")
    parser.add_argument(
        "command",
        choices=[
            "start-proxy",
            "stop-proxy",
            "boot-reconcile",
            "apply-emulator-config",
            "install-service-unit",
            "ensure-boot-hook",
            "remove-boot-hook",
            "enable-autostart",
            "disable-autostart",
            "autostart-status",
            "cached-games",
            "cached-games-count",
            "cached-unlock-titles",
            "remove-cached-game",
            "clear-cached-games",
            "pending-awards",
            "pending-awards-count",
            "home-status",
            "browser-root",
            "browser-list",
            "browser-list-fast",
            "cache-rom",
            "cache-roms",
            "export-cached-ids",
            "cache-folder-listing",
            "smart-cache-status",
            "run-smart-cache",
            "update-status",
            "install-update",
            "service-status",
            "status",
            "run-service",
            "ui-image",
            "text-image",
            "menu",
            "menu-sdl",
            "probe-online",
        ],
        help="Action to perform",
    )
    parser.add_argument(
        "--retroarch-cfg",
        dest="retroarch_cfg",
        help="Override RetroArch config path",
    )
    parser.add_argument(
        "--path",
        dest="path",
        help="Filesystem path for browser and cache commands",
    )
    parser.add_argument(
        "--json",
        dest="as_json",
        action="store_true",
        help="Print machine-readable output",
    )
    parser.add_argument(
        "--paths-file",
        dest="paths_file",
        help="File containing one ROM path per line for cache-roms",
    )
    parser.add_argument(
        "--game-id",
        dest="game_id",
        type=int,
        help="Game id for cached game commands",
    )
    parser.add_argument(
        "--output",
        dest="output",
        help="Output file path for commands that write files",
    )
    parser.add_argument(
        "--text",
        dest="text",
        help="Text payload for commands that render text",
    )
    parser.add_argument(
        "--image-width",
        dest="image_width",
        type=int,
        help="Override rendered image width",
    )
    parser.add_argument(
        "--image-height",
        dest="image_height",
        type=int,
        help="Override rendered image height",
    )
    parser.add_argument(
        "--font-scale",
        dest="font_scale",
        type=int,
        help="Override rendered font scale",
    )
    parser.add_argument(
        "--platform",
        dest="platform",
        help="Platform name for platform-specific commands",
    )
    args = parser.parse_args()

    try:
        if args.command != "run-service":
            configure_logging()

        config_data = load_config()
        cfg_path = (
            args.retroarch_cfg
            or config_data.get("retroarch_cfg")
            or detect_retroarch_cfg()
        )

        if args.command == "run-service":
            run_service_foreground(config_data)
            return

        if args.command == "menu":
            run_menu_sdl(sys.argv[0])
            return

        if args.command == "menu-sdl":
            run_menu_sdl(sys.argv[0])
            return

        if args.command == "ui-image":
            if not args.output:
                raise ValueError("ui-image requires --output")
            write_status_image(
                args.output,
                image_width=args.image_width or 0,
                image_height=args.image_height or 0,
            )
            return

        if args.command == "text-image":
            if not args.output:
                raise ValueError("text-image requires --output")
            if args.text is None:
                raise ValueError("text-image requires --text")
            write_text_image(
                args.output,
                args.text,
                image_width=args.image_width or 0,
                image_height=args.image_height or 0,
                font_scale=args.font_scale or 0,
            )
            return

        if args.command == "start-proxy":
            for line in _apply_proxy(config_data, cfg_path):
                print(line)
            return

        if args.command == "boot-reconcile":
            if is_autostart_enabled(config_data):
                for line in _apply_proxy(config_data, cfg_path):
                    print(line)
            else:
                for line in _revert_proxy_config(config_data, args.retroarch_cfg or cfg_path):
                    print(line)
            return

        if args.command == "install-service-unit":
            # Keeps the unit definition in one place: the installer calls this
            # rather than writing its own copy, so an upgrade always lands the
            # current template instead of whatever the old installer shipped.
            if running_on_darkos():
                systemd_install_service()
                print("Service unit installed")
            else:
                print("No service unit to install on this platform")
            return

        if args.command == "apply-emulator-config":
            for line in _patch_emulator_configs(config_data, cfg_path):
                print(line)
            return

        if args.command == "ensure-boot-hook":
            ensure_boot_hook(config_data)
            print("Boot hook installed")
            return

        if args.command == "remove-boot-hook":
            remove_boot_hook(config_data)
            print("Boot hook removed")
            return

        if args.command == "stop-proxy":
            for line in safe_stop_proxy(config_data, args.retroarch_cfg or cfg_path):
                print(line)
            return

        if args.command == "enable-autostart":
            enable_autostart(config_data)
            print("Autostart enabled")
            return

        if args.command == "disable-autostart":
            disable_autostart(config_data)
            print("Autostart disabled")
            return

        if args.command == "autostart-status":
            print("enabled" if is_autostart_enabled(config_data) else "disabled")
            return

        if args.command == "cached-games":
            storage = Storage()
            try:
                games = list_cached_games(storage)
                unlock_counts = cached_unlock_counts(storage) if games else {}

                if args.as_json:
                    print(json.dumps(
                        [
                            {
                                "game_id": game.game_id,
                                "title": game.title,
                                "unlocks": unlock_counts.get(game.game_id),
                            }
                            for game in games
                        ],
                        separators=(",", ":"),
                    ))
                    return

                if not games:
                    return

                for game in games:
                    unlock_count = unlock_counts.get(game.game_id)
                    suffix = (
                        f" ({unlock_count} unlocks)" if unlock_count is not None else ""
                    )
                    print(f"{game.title}{suffix} ##GAMEID:{game.game_id}")
            finally:
                storage.close()
            return

        if args.command == "cached-games-count":
            storage = Storage()
            try:
                print(len(list_cached_games(storage)))
            finally:
                storage.close()
            return

        if args.command == "cached-unlock-titles":
            if args.game_id is None or args.game_id <= 0:
                raise ValueError("cached-unlock-titles requires --game-id")

            storage = Storage()
            try:
                titles = cached_unlock_titles(storage, args.game_id)
                for title in titles:
                    print(title)
            finally:
                storage.close()
            return

        if args.command == "remove-cached-game":
            if args.game_id is None or args.game_id <= 0:
                raise ValueError("remove-cached-game requires --game-id")

            storage = Storage()
            try:
                remove_cached_game(storage, args.game_id)
                print(f"Removed cached game {args.game_id}")
            finally:
                storage.close()
            return

        if args.command == "clear-cached-games":
            storage = Storage()
            try:
                clear_cached_games(storage)
                print("Cleared cached games")
            finally:
                storage.close()
            return

        if args.command == "pending-awards":
            storage = Storage()
            try:
                awards = list_pending_awards(storage)
                if not awards:
                    print("No pending awards")
                    return

                for index, award in enumerate(awards, start=1):
                    print(f"{index}. {award.summary_text}")
            finally:
                storage.close()
            return

        if args.command == "pending-awards-count":
            storage = Storage()
            try:
                print(len(list_pending_awards(storage)))
            finally:
                storage.close()
            return

        if args.command == "home-status":
            storage = Storage()
            try:
                service = service_status()
                print(
                    json.dumps(
                        {
                            "cached_games_count": len(list_cached_games(storage)),
                            "pending_awards_count": len(list_pending_awards(storage)),
                            "service_running": bool(service.get("running")),
                            "service_pid": service.get("pid"),
                            "autostart_enabled": is_autostart_enabled(config_data),
                            "is_online": bool(load_online_state()),
                        },
                        separators=(",", ":"),
                    )
                )
            finally:
                storage.close()
            return

        if args.command == "probe-online":
            save_online_state(online_check(config_data))
            return

        if args.command == "browser-root":
            print(resolve_rom_root(config_data))
            return

        if args.command == "browser-list":
            if not args.path:
                raise ValueError("browser-list requires --path")

            current_dir = Path(args.path).expanduser()
            if not current_dir.exists() or not current_dir.is_dir():
                raise ValueError(f"Invalid browser directory: {current_dir}")

            storage = Storage()
            try:
                for entry in describe_browser_entries(current_dir, storage):
                    print(
                        "\t".join(
                            [
                                "1" if entry.is_dir else "0",
                                "1" if entry.is_cached else "0",
                                str(entry.path),
                                entry.name,
                            ]
                        )
                    )
            finally:
                storage.close()
            return

        if args.command == "browser-list-fast":
            if not args.path:
                raise ValueError("browser-list-fast requires --path")

            current_dir = Path(args.path).expanduser()
            if not current_dir.exists() or not current_dir.is_dir():
                raise ValueError(f"Invalid browser directory: {current_dir}")

            for entry in describe_browser_entries_fast(current_dir):
                print(
                    "\t".join(
                        [
                            "1" if entry.is_dir else "0",
                            "1" if entry.is_cached else "0",
                            str(entry.path),
                            entry.name,
                        ]
                    )
                )
            return

        if args.command == "cache-roms":
            if not args.paths_file:
                raise ValueError("cache-roms requires --paths-file")

            paths_file = Path(args.paths_file).expanduser()
            if not paths_file.is_file():
                raise ValueError(f"Invalid paths file: {paths_file}")

            rom_paths = [
                Path(line.strip()).expanduser()
                for line in paths_file.read_text().splitlines()
                if line.strip()
            ]
            if not rom_paths:
                raise ValueError("cache-roms paths file is empty")

            cached_count = 0
            failed_count = 0
            total = len(rom_paths)
            storage = Storage()
            try:
                for index, rom_path in enumerate(rom_paths, start=1):
                    apply_scan_batch_cooldown(index - 1)
                    label = rom_path.name
                    if not rom_path.is_file():
                        failed_count += 1
                        print(f"FAIL {index}/{total} {label}: not found", flush=True)
                        continue
                    try:
                        result = add_rom_to_cache(rom_path, storage, config_data)
                    except Exception as error:
                        failed_count += 1
                        print(f"FAIL {index}/{total} {label}: {error}", flush=True)
                        continue
                    if result.success:
                        cached_count += 1
                        print(f"OK {index}/{total} {label}", flush=True)
                    else:
                        failed_count += 1
                        print(
                            f"FAIL {index}/{total} {label}: {result.message}",
                            flush=True,
                        )
            finally:
                storage.close()

            print(f"DONE cached={cached_count} failed={failed_count}", flush=True)
            return

        if args.command == "export-cached-ids":
            storage = Storage()
            try:
                export_cached_game_ids(storage)
            finally:
                storage.close()
            print(str(CACHED_IDS_FILE))
            return

        if args.command == "cache-rom":
            if not args.path:
                raise ValueError("cache-rom requires --path")

            rom_path = Path(args.path).expanduser()
            if not rom_path.exists() or not rom_path.is_file():
                raise ValueError(f"Invalid ROM path: {rom_path}")

            storage = Storage()
            try:
                result = add_rom_to_cache(rom_path, storage, config_data)
            finally:
                storage.close()

            if args.as_json:
                print(json.dumps(
                    {"success": result.success, "message": result.message},
                    separators=(",", ":"),
                ))
                if not result.success:
                    raise SystemExit(1)
                return

            if not result.success:
                raise RuntimeError(result.message)

            print(result.message)
            return

        if args.command == "cache-folder-listing":
            if not args.path:
                raise ValueError("cache-folder-listing requires --path")

            current_dir = Path(args.path).expanduser()
            if not current_dir.exists() or not current_dir.is_dir():
                raise ValueError(f"Invalid browser directory: {current_dir}")

            storage = Storage()
            try:

                def on_progress(progress) -> None:
                    print(
                        json.dumps(
                            {
                                "type": "progress",
                                "scanned": progress.scanned,
                                "total": progress.total,
                                "cached": progress.cached,
                                "current_label": progress.current_label,
                            },
                            separators=(",", ":"),
                        ),
                        flush=True,
                    )

                result = run_folder_cache(
                    storage,
                    config_data,
                    current_dir,
                    should_abort=should_abort_from_env,
                    on_progress=on_progress,
                )
            finally:
                storage.close()

            if result.total <= 0:
                raise RuntimeError("No ROM files in this folder")

            print(
                json.dumps(
                    {
                        "type": "result",
                        "scanned": result.scanned,
                        "total": result.total,
                        "cached": result.cached,
                        "skipped": result.skipped,
                        "limit_reached": result.limit_reached,
                    },
                    separators=(",", ":"),
                )
            )
            return

        if args.command == "smart-cache-status":
            storage = Storage()
            try:
                cached_rom_paths = load_cached_rom_paths(storage)
                history_paths = [
                    path
                    for path in load_content_history_paths(config_data)
                    if normalize_cached_rom_path(path) not in cached_rom_paths
                ]
                total_candidates = min(len(history_paths), SMART_CACHE_LIMIT)
                LOGGER.info(
                    "Smart Cache status path-aware candidates=%s capped=%s",
                    len(history_paths),
                    total_candidates,
                )
                print(
                    json.dumps(
                        {
                            "found_history": total_candidates > 0,
                            "total_candidates": total_candidates,
                        },
                        separators=(",", ":"),
                    )
                )
            finally:
                storage.close()
            return

        if args.command == "run-smart-cache":
            storage = Storage()
            try:
                credentials = resolve_credentials(storage, config_data)
                if credentials is None:
                    LOGGER.info(
                        "Smart Cache run blocked: missing RetroAchievements credentials"
                    )
                    raise RuntimeError("RetroAchievements login required")
                if not online_check(config_data):
                    LOGGER.info("Smart Cache run blocked: online check failed")
                    raise RuntimeError("Smart Cache requires an online connection")
                LOGGER.info("Smart Cache run starting")

                def on_progress(progress) -> None:
                    print(
                        json.dumps(
                            {
                                "type": "progress",
                                "scanned": progress.scanned,
                                "total": progress.total,
                                "cached": progress.cached,
                                "current_label": progress.current_label,
                            },
                            separators=(",", ":"),
                        ),
                        flush=True,
                    )

                result = run_smart_cache(
                    storage,
                    config_data,
                    SMART_CACHE_LIMIT,
                    should_abort=should_abort_from_env,
                    on_progress=on_progress,
                )
                print(
                    json.dumps(
                        {
                            "type": "result",
                            "scanned": result.scanned,
                            "total": result.total,
                            "cached": result.cached,
                            "skipped": result.skipped,
                            "limit_reached": result.limit_reached,
                        },
                        separators=(",", ":"),
                    )
                )
            finally:
                storage.close()
            return

        if args.command == "service-status":
            service = service_status()
            service_line = (
                f"Service running: {'yes' if service.get('running') else 'no'}"
            )
            if service.get("running") and service.get("pid"):
                service_line += f" | PID: {service['pid']}"
            print(service_line)
            return

        if args.command == "install-update":
            if not args.platform:
                raise ValueError("install-update requires --platform")

            info = update_status(args.platform, force=True)
            if not info.asset_url:
                raise RuntimeError(f"No {args.platform} asset in the latest release")

            stop_service_process()
            archive = download_onion_update_archive(info.asset_url)
            install_onion_update_archive(archive, DEFAULT_ONION_APP_DIR, "App")

            result = {"installed": True, "version": info.latest_version}
            print(json.dumps(result, separators=(",", ":")) if args.as_json
                  else f"Installed {info.latest_version}")
            return

        if args.command == "update-status":
            if not args.platform:
                raise ValueError("update-status requires --platform")
            print(
                json.dumps(
                    update_status(args.platform).to_dict(),
                    separators=(",", ":"),
                )
            )
            return

        status = status_retroarch_cfg(cfg_path, config_data)
        service = service_status()
        print(f"Config: {status['cfg_path']}")
        print(f"Exists: {'yes' if status['exists'] else 'no'}")
        print(f"Patched: {'yes' if status['is_patched'] else 'no'}")
        print(f"State file: {'present' if status['state_present'] else 'missing'}")
        if status["exists"]:
            print(
                f"Hardcore enabled: {'yes' if status.get('hardcore_enabled', False) else 'no'}"
            )
        service_line = f"Service running: {'yes' if service.get('running') else 'no'}"
        if service.get("running") and service.get("pid"):
            service_line += f" | PID: {service['pid']}"
        print(service_line)
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        if not CONFIG_FILE.exists():
            print(
                f"Optional config file: {CONFIG_FILE} (supports proxy_host, proxy_port, retroarch_cfg)",
                file=sys.stderr,
            )
        sys.exit(1)


if __name__ == "__main__":
    main()
