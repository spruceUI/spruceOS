from __future__ import annotations

import os
import subprocess
import sys
import threading
import traceback
import time
from pathlib import Path

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
from .config import (
    APP_VERSION,
    CONFIG_DIR,
    DEFAULT_ALLIUM_APP_DIR,
    DEFAULT_DARKOS_HOME,
    DEFAULT_ONION_APP_DIR,
    load_config,
    running_on_allium,
    running_on_onion,
    running_on_shared_miyoo_stack,
    running_on_mini_sdl_stack,
    running_on_rocknix,
    running_on_spruce,
    running_on_darkos,
    save_config,
)
from .platform import (
    autostart_supported,
    disable_autostart,
    enable_autostart,
    is_autostart_enabled,
    resolve_retroarch_cfg,
    resolve_rom_root,
)
from .pending_awards import delete_pending_award, list_pending_awards
from .network import online_check
from .retroarch_cfg import (
    enforce_patched_cfg,
    load_retroarch_credentials,
    patch_retroarch_cfg,
    revert_retroarch_cfg,
)
from .image_cache import shutdown_image_downloads
from .rom_browser import (
    MAX_CACHED_GAMES,
    add_rom_to_cache,
    cached_unlock_badge_paths,
    cached_unlock_count,
    cached_unlock_titles,
    clear_cached_games,
    directory_has_supported_roms,
    ensure_game_preview,
    list_scannable_files_recursive,
    list_browser_entries,
    list_cached_games,
    remove_cached_game,
)
from .service import service_status, start_service_process, stop_service_process
from .knulli_service import (
    disable_service_autostart,
    enable_service_autostart,
    service_autostart_enabled,
    service_mode_active,
    start_service,
    stop_service,
)
from .smart_cache import (
    SMART_CACHE_LIMIT,
    load_content_history_paths,
    run_folder_cache,
    run_smart_cache,
    should_offer_smart_cache,
)
from .state import load_patch_state, save_patch_state
from .storage import Storage
from . import storage_corruption
from .update import (
    download_knulli_update_installer,
    download_muos_update_archive,
    download_onion_update_archive,
    install_muos_update_archive,
    install_onion_update_archive,
    update_status,
)
from .log_uploader import (
    SUPPORTED_ONION_VERSION_PREFIX,
    onion_os_version,
    onion_version_supported,
    report_storage_corruption,
    upload_logs,
)
from .menu_input import (
    BTN_DPAD_DOWN,
    BTN_DPAD_LEFT,
    BTN_DPAD_RIGHT,
    BTN_DPAD_UP,
    BTN_EAST,
    BTN_SELECT,
    BTN_SOUTH,
    BTN_START,
    BTN_TL,
    BTN_TR,
    KEY_BACKSPACE,
    KEY_DOWN,
    KEY_ENTER,
    KEY_ESC,
    KEY_LEFT,
    KEY_Q,
    KEY_RIGHT,
    KEY_S,
    KEY_SPACE,
    KEY_UP,
    close_input_devices,
    open_input_devices,
    read_keys,
)

SDL_LOG_PATH = CONFIG_DIR / "menu-sdl.log"
STALE_HOOK_PATH = Path("/userdata/system/scripts/RAOfflineProxy_game_hook.sh")
BACKGROUND_COLOR = (0, 0, 0)
PRIMARY_COLOR = (28, 81, 130)
SECONDARY_COLOR = (210, 164, 72)
TEXT_COLOR = (255, 255, 255)
SELECTED_COLOR = SECONDARY_COLOR
STATUS_COLOR = (180, 180, 180)
SECONDARY_TEXT_COLOR = (110, 110, 110)
ERROR_COLOR = (200, 70, 60)
ERROR_SECONDS = 3
FPS = 60
LEFT_MARGIN = 32
GROUP_GAP = 14
MAIN_MENU_STATE_REFRESH_SECONDS = 1.0
PREVIEW_RETRY_SECONDS = 2.0
KNULLI_FONT_CANDIDATES = [
    "DejaVu Sans Mono",
    "Monospace",
    "DejaVu Sans",
    "DejaVu Sans Condensed",
    "Noto Sans JP",
    "Noto Sans SC",
    "Noto Sans KR",
    "Noto Sans TC",
    "Noto Sans HK",
]
MUOS_FONT_REGULAR = Path("/usr/share/fonts/liberation/LiberationMono-Regular.ttf")
MUOS_FONT_BOLD = Path("/usr/share/fonts/liberation/LiberationMono-Bold.ttf")
# Font files loaded by explicit path (SDL_ttf reads them directly, so no
# fontconfig is needed — ROCKNIX ships no fc-list, which makes
# pygame.font.match_font() return nothing). Each entry is (regular, bold);
# when a face has no dedicated bold file, bold is synthesized via set_bold.
FONT_FILE_CANDIDATES = [
    (MUOS_FONT_REGULAR, MUOS_FONT_BOLD),
    (
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf"),
    ),
]
LOGO_PATH = Path(__file__).resolve().parent / "logo-320.png"
ASSETS_DIR = Path(__file__).resolve().parent / "assets"
SUPPORT_SUBTITLE = "Free & open source, made in my spare time"
SUPPORT_DESCRIPTION = "If it's been useful to you, a small donation helps keep it going. Thank you!"
SUPPORT_DONATE_URL = "https://raofflineproxy.com/donate.html"
# Monthly-only: Stripe can't combine a customer-chosen amount with a
# recurring price, so unlike one-time (any amount), monthly is a fixed set
# of preset tiers, each its own Payment Link/QR image.
SUPPORT_ONETIME_QR = ASSETS_DIR / "support_qr_onetime.png"
SUPPORT_MONTHLY_TIERS: list[tuple[str, str, Path]] = [
    ("$1 / month", "monthly_1", ASSETS_DIR / "support_qr_monthly_1.png"),
    ("$3 / month", "monthly_3", ASSETS_DIR / "support_qr_monthly_3.png"),
    ("$5 / month", "monthly_5", ASSETS_DIR / "support_qr_monthly_5.png"),
    ("$8 / month", "monthly_8", ASSETS_DIR / "support_qr_monthly_8.png"),
    ("$10 / month", "monthly_10", ASSETS_DIR / "support_qr_monthly_10.png"),
    ("$15 / month", "monthly_15", ASSETS_DIR / "support_qr_monthly_15.png"),
]
# Onion has no fontconfig and no reliable system-wide monospace font (its
# only TTFs are bundled inside individual, optional third-party apps), so a
# monospace face ships directly alongside this module rather than being
# looked up on the filesystem.
ONION_FONT_REGULAR = Path(__file__).resolve().parent / "font-mono.ttf"
ONION_FONT_BOLD = Path(__file__).resolve().parent / "font-mono-bold.ttf"
MUOS_SDCARD_ROOT = Path("/mnt/sdcard/ROMS")
KEY_NAMES = {
    103: "KEY_UP",
    108: "KEY_DOWN",
    105: "KEY_LEFT",
    106: "KEY_RIGHT",
    28: "KEY_ENTER",
    57: "KEY_SPACE",
    1: "KEY_ESC",
    14: "KEY_BACKSPACE",
    16: "KEY_Q",
    31: "KEY_S",
    304: "BTN_SOUTH",
    305: "BTN_EAST",
    306: "BTN_C",
    307: "BTN_NORTH",
    308: "BTN_WEST",
    309: "BTN_Z",
    310: "BTN_TL (L1)",
    311: "BTN_TR (R1)",
    312: "BTN_TL2 (L2)",
    313: "BTN_TR2 (R2)",
    314: "BTN_SELECT",
    315: "BTN_START",
    316: "BTN_MODE",
    317: "BTN_THUMBL",
    318: "BTN_THUMBR",
    544: "BTN_DPAD_UP",
    545: "BTN_DPAD_DOWN",
    546: "BTN_DPAD_LEFT",
    547: "BTN_DPAD_RIGHT",
}
# Calibration accepts any button that isn't a d-pad direction, rather than a
# fixed whitelist: gpio-keys-polled handhelds (Onion) emit raw evdev KEY_*
# codes for their face buttons (e.g. KEY_LEFTCTRL), not the BTN_SOUTH/BTN_EAST
# joystick codes other platforms' controllers use, and there's no complete
# enumeration of every device's button codes to whitelist against.
CALIBRATION_EXCLUDED_KEYS = {
    KEY_UP,
    KEY_DOWN,
    KEY_LEFT,
    KEY_RIGHT,
    BTN_DPAD_UP,
    BTN_DPAD_DOWN,
    BTN_DPAD_LEFT,
    BTN_DPAD_RIGHT,
}


ONION_DEFAULT_PANEL_SIZE = (640, 480)
ONION_SCREEN_RESOLUTION_FILE = Path("/tmp/screen_resolution")


def _onion_panel_size() -> tuple[int, int]:
    """The vendored "Mini" SDL2 driver ignores whatever size is passed to
    SDL_SetDisplayMode/pygame.display.set_mode: it self-detects the real
    framebuffer via its own `fbset` probe at init (640x480, or 750x560 on
    devices whose fbset mode reports "750", e.g. the Miyoo Mini Flip) and
    presents at that size
    regardless. So the window/texture here must match what the driver will
    actually use, or the two sizes fight each other. Onion's own
    runtime.sh writes the same underlying panel probe result to
    /tmp/screen_resolution, so read that rather than re-deriving it (and
    rather than assuming 640x480, which is only one of Onion's panel
    variants).
    """
    try:
        raw = ONION_SCREEN_RESOLUTION_FILE.read_text(encoding="utf-8").strip()
        width_str, height_str = raw.split("x", 1)
        width, height = int(width_str), int(height_str)
        if width > 0 and height > 0:
            return (width, height)
    except (OSError, ValueError):
        pass
    return ONION_DEFAULT_PANEL_SIZE


def _init_onion_display(pygame):
    """Onion's SDL2 video driver only presents through the SDL_Renderer +
    streaming-texture path; SDL_UpdateWindowSurface (what pygame.display.flip
    normally uses) silently no-ops there. Route flip() through a renderer
    instead, keeping the surface pygame draws onto in RGB565 (the only pixel
    format that doesn't crash the renderer's texture upload on this driver).
    """
    from pygame._sdl2.video import Renderer, Texture, Window

    panel_size = _onion_panel_size()
    pygame.display.set_mode(panel_size, 0)
    window = Window.from_display_module()
    renderer = Renderer(window, accelerated=-1, vsync=False)
    draw_surface = pygame.Surface(panel_size, depth=16)

    try:
        texture = Texture(renderer, panel_size, streaming=True)
        texture_surface = draw_surface
        log_menu_sdl(f"onion display texture native size={panel_size[0]}x{panel_size[1]}")
    except RuntimeError as exc:
        # The vendored "Mini" SDL2 driver's swiftshader renderer caps
        # streaming textures at 640x480 regardless of the actual panel
        # (e.g. the Miyoo Mini Flip's 750x560 screen exceeds it). Present
        # through a capped-size texture and let SDL_RenderCopy scale it
        # back up to the real panel size. The renderer is sized from the
        # live framebuffer at init, so this also trips when the panel is
        # 560p but Onion launched the app in MainUI's 640x480 mode (i.e.
        # the App/RAOfflineProxy/full_resolution marker is missing).
        log_menu_sdl(
            f"onion display texture {panel_size[0]}x{panel_size[1]} rejected "
            f"({exc}), scaling through "
            f"{ONION_DEFAULT_PANEL_SIZE[0]}x{ONION_DEFAULT_PANEL_SIZE[1]}"
        )
        texture_surface = pygame.Surface(ONION_DEFAULT_PANEL_SIZE, depth=16)
        texture = Texture(renderer, ONION_DEFAULT_PANEL_SIZE, streaming=True)

    def _present() -> None:
        if texture_surface is draw_surface:
            texture.update(draw_surface)
        else:
            pygame.transform.scale(draw_surface, texture_surface.get_size(), texture_surface)
            texture.update(texture_surface)
        renderer.clear()
        texture.draw(dstrect=(0, 0, panel_size[0], panel_size[1]))
        renderer.present()

    pygame.display.flip = _present
    return draw_surface


def run_menu_sdl(command_runner: str) -> None:
    pygame = None
    log_menu_sdl(
        f"run_menu_sdl start python={sys.version.split()[0]} executable={sys.executable}"
    )
    try:
        import pygame

        pygame.init()
        pygame.font.init()

        if running_on_mini_sdl_stack():
            # No fallback: the vendored SDL2 carries no driver but "Mini", which presents
            # only through this renderer path. A plain surface would come back as a menu
            # that runs but never draws, so failing here and returning to the launcher is
            # the better outcome.
            surface = _init_onion_display(pygame)
        else:
            try:
                surface = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
            except pygame.error as exc:
                configured_driver = os.environ.get("SDL_VIDEODRIVER", "")
                if configured_driver != "" and "not available" in str(exc):
                    log_menu_sdl(
                        f"display fallback from driver={configured_driver} error={exc}"
                    )
                    os.environ.pop("SDL_VIDEODRIVER", None)
                    pygame.display.quit()
                    pygame.display.init()
                    surface = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
                else:
                    raise

        try:
            log_menu_sdl(
                f"display probe driver={pygame.display.get_driver()} "
                f"num_displays={pygame.display.get_num_displays()} "
                f"desktop_sizes={pygame.display.get_desktop_sizes()}"
            )
        except pygame.error as exc:
            log_menu_sdl(f"display probe failed: {exc}")

        refuse_headless_driver(pygame.display.get_driver())

        width, height = surface.get_size()
        log_menu_sdl(f"display set_mode surface_size={width}x{height}")
        session = MenuSdlSession(command_runner, surface, width, height, pygame)
        session.run()
    except Exception:
        log_menu_sdl(traceback.format_exc().rstrip())
        raise
    finally:
        # Before pygame.quit(), so the window is not still up while queued badge
        # downloads are cancelled.
        shutdown_image_downloads()
        restart_muos_frontend()
        if pygame is not None:
            pygame.quit()


HEADLESS_SDL_DRIVERS = ("dummy", "offscreen")
MENU_READY_FILE_ENV = "RAOFFLINEPROXY_MENU_READY_FILE"


def refuse_headless_driver(driver: str) -> None:
    # SDL falls back to these when it finds no display it can drive. The menu then runs
    # but draws nowhere, and with nothing on screen to exit by, the device looks frozen.
    # Asking for one explicitly is a deliberate choice and still allowed.
    if driver in HEADLESS_SDL_DRIVERS and os.environ.get("SDL_VIDEODRIVER") != driver:
        raise RuntimeError(f"SDL found no usable display and fell back to {driver}")


def signal_menu_ready() -> None:
    ready_file = os.environ.get(MENU_READY_FILE_ENV)
    if not ready_file:
        return
    try:
        Path(ready_file).touch()
    except OSError as exc:
        log_menu_sdl(f"menu ready signal failed: {exc}")


_DEBUG_DUMP_FRAME_PATH = CONFIG_DIR / "debug_frame.png"
_debug_frame_dumped = False


def maybe_dump_debug_frame(surface, pygame) -> None:
    global _debug_frame_dumped
    if _debug_frame_dumped or os.environ.get("RAOFFLINEPROXY_DEBUG_DUMP_FRAME") != "1":
        return
    _debug_frame_dumped = True
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        pygame.image.save(surface, str(_DEBUG_DUMP_FRAME_PATH))
        log_menu_sdl(f"debug frame dumped to {_DEBUG_DUMP_FRAME_PATH}")
    except Exception as exc:
        log_menu_sdl(f"debug frame dump failed: {exc}")


def log_menu_sdl(message: str) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    with SDL_LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(f"{timestamp} {message}\n")


def log_action_failure(action: str, exc: Exception) -> None:
    log_menu_sdl(f"{action} failed error={exc}")
    log_menu_sdl(traceback.format_exc().rstrip())


def remove_stale_hook() -> None:
    if STALE_HOOK_PATH.exists():
        STALE_HOOK_PATH.unlink()


def running_on_muos() -> bool:
    return Path("/opt/muos/script/archive").exists()


def restart_muos_frontend() -> None:
    if not running_on_muos():
        return

    subprocess.Popen(
        ["setsid", "-f", "/opt/muos/script/mux/frontend.sh", "appmenu"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def runtime_config() -> tuple[dict, str]:
    config_data = load_config()
    cfg_path = resolve_retroarch_cfg(config_data)
    return config_data, cfg_path


def start_proxy_inline() -> bool:
    """Starts the proxy. Returns True when RetroArch's cfg was missing and skipped."""
    config_data, cfg_path = runtime_config()
    remove_stale_hook()
    patch_result = patch_retroarch_cfg(cfg_path, config_data)
    enforce_patched_cfg(cfg_path, config_data)
    batocera = patch_batocera_conf(config_data)
    ppsspp = patch_ppsspp_ini(config_data)
    dolphin = patch_dolphin_ini(config_data)
    patch_state = load_patch_state() or {}
    store_batocera_previous(patch_state, batocera)
    store_ppsspp_previous(patch_state, ppsspp)
    store_dolphin_previous(patch_state, dolphin)
    save_patch_state(patch_state)
    start_service_process(config_data)
    return not patch_result.get("exists", True)


def stop_proxy_inline() -> None:
    config_data, cfg_path = runtime_config()
    remove_stale_hook()
    patch_state = load_patch_state() or {}
    revert_cfg_path = patch_state.get("cfg_path") or cfg_path
    service = stop_service_process()
    previous_batocera = patch_state.get("batocera_previous", {})
    revert_batocera_conf(config_data, previous_batocera)
    revert_ppsspp_ini(config_data, patch_state.get("ppsspp_previous", {}))
    revert_dolphin_ini(config_data, patch_state.get("dolphin_previous", {}))

    if patch_state:
        revert_retroarch_cfg(revert_cfg_path, patch_state, config_data=config_data)
        return

    if not service.get("already_stopped"):
        try:
            revert_retroarch_cfg(revert_cfg_path, config_data=config_data)
        except Exception:
            pass
        return

    try:
        revert_retroarch_cfg(revert_cfg_path, config_data=config_data)
    except Exception:
        pass


class MenuSdlSession:
    def __init__(
        self, command_runner: str, surface, width: int, height: int, pygame
    ) -> None:
        self.command_runner = command_runner
        self.surface = surface
        self.width = width
        self.height = height
        self.pygame = pygame
        self.config_data = load_config()
        self.running = True
        self.onion_unsupported = running_on_onion() and not onion_version_supported()
        if self.onion_unsupported:
            self.view = "unsupported_onion"
        else:
            self.view = "controller_calibration" if self.needs_controller_calibration() else "main"
        self.selected_index = 0
        self.scroll_offset = 0
        self.message: tuple[str, float] | None = None
        self.storage = Storage()
        self.cached_games = []
        self.pending_awards = []
        self.active_game = None
        self.active_pending_award = None
        self.key_log: list[int] = []
        self.browser_dir: Path | None = None
        self.browser_root: Path | None = None
        self.browser_entries: list[Path] = []
        self.view_positions: dict[str, tuple[int, int]] = {}
        self.browser_positions: dict[str, tuple[int, int]] = {}
        self.smart_cache_prompt_available = False
        self.smart_cache_prompt_count = 0
        self.smart_cache_in_progress = False
        self.smart_cache_progress_text: str | None = None
        self.smart_cache_result: tuple[str, float] | None = None
        self.smart_cache_thread: threading.Thread | None = None
        self.cache_progress_text: str | None = None
        self.cache_progress_title: str | None = None
        self.cache_result: tuple[str, float] | None = None
        self.cache_worker_thread: threading.Thread | None = None
        self.cache_abort_requested = False
        self.cache_completed = False
        self.cache_completion_message: str | None = None
        self.cache_return_view = "cached_games"
        self.cache_return_browser_dir: Path | None = None
        self.cache_return_browser_restore = False
        self.log_upload_thread: threading.Thread | None = None
        self.log_upload_progress_text: str | None = None
        self.log_upload_result: tuple[bool, str] | None = None
        self.storage_corruption_active = False
        self.storage_corruption_notice_seen = False
        self.storage_corruption_lost_awards: int | None = None
        self.storage_corruption_done = False
        self.preview_surface = None
        self.preview_game_id = None
        self.achievement_preview_surface = None
        self.achievement_preview_game_id = None
        self.achievement_preview_title = None
        self.logo_surface = None
        self.support_qr_surface_cache: dict[str, object] = {}
        # "onetime" or one of SUPPORT_MONTHLY_TIERS' keys — set right before entering
        # support_me_qr so it knows which QR/label to show, and go_back()/dismiss know
        # which list to return to.
        self.support_selected_tier: str | None = None
        self.support_qr_return_view = "support_me"
        self.main_state_refreshed_at = 0.0
        self.main_running = False
        self.main_online = False
        self.main_logged_in = False
        self.main_autostart_supported = False
        self.main_autostart_enabled = False
        self.main_update_available = False
        self.main_update_version = None
        self.main_update_asset_url = None
        self.main_update_dialog_seen = False
        self.calibration_confirm_button = self.configured_confirm_button()
        self.calibration_cancel_button = self.configured_cancel_button()
        self.calibration_step = (
            "done"
            if self.calibration_complete()
            else ("confirm" if self.calibration_confirm_button is None else "cancel")
        )
        self.clear_cache_return_view = "cached_games"
        self.active_game_unlock_game_id = None
        self.active_game_unlock_count_cached = None
        self.active_game_unlock_titles_cached: list[str] = []
        self._badge_path_cache: dict[str, object] = {}
        self._badge_surface_cache: dict[str, object] = {}
        self.input_handles = open_input_devices()
        self.last_key_press: dict[int, float] = {}
        self.title_font = self.load_font(max(30, height // 19), bold=True)
        self.status_font = self.load_font(max(20, height // 30))
        self.item_font = self.load_font(max(22, height // 30), bold=False)
        self.meta_font = self.load_font(max(16, height // 44), bold=False)
        self.clock = pygame.time.Clock()

        self.refresh_main_menu_state(force=True)
        self.refresh_cached_games()

    def load_font(self, size: int, bold: bool = False):
        if running_on_shared_miyoo_stack():
            font_path = ONION_FONT_BOLD if bold else ONION_FONT_REGULAR
            if font_path.exists():
                return self.pygame.font.Font(str(font_path), size)
            font = self.pygame.font.Font(None, size)
            font.set_bold(bold)
            return font

        if running_on_muos() or running_on_rocknix():
            for regular_path, bold_path in FONT_FILE_CANDIDATES:
                chosen = bold_path if bold else regular_path
                synthesize_bold = False
                if not chosen.exists():
                    chosen = regular_path
                    synthesize_bold = bold
                if chosen.exists():
                    font = self.pygame.font.Font(str(chosen), size)
                    if synthesize_bold:
                        font.set_bold(True)
                    return font
            font = self.pygame.font.Font(None, size)
            font.set_bold(bold)
            return font

        for font_name in KNULLI_FONT_CANDIDATES:
            font_path = self.pygame.font.match_font(font_name)
            if font_path is None:
                continue

            font = self.pygame.font.Font(font_path, size)
            font.set_bold(bold)
            return font

        font = self.pygame.font.Font(None, size)
        font.set_bold(bold)
        return font

    def run(self) -> None:
        try:
            first_frame = True
            while self.running:
                self.handle_events()
                self.handle_raw_input()
                self.render()
                if first_frame:
                    signal_menu_ready()
                    first_frame = False
                self.clock.tick(FPS)
        finally:
            close_input_devices(self.input_handles)
            self.storage.close()

    def render(self) -> None:
        self.surface.fill(BACKGROUND_COLOR)

        if self.view == "unsupported_onion":
            self.render_unsupported_onion_view()
            maybe_dump_debug_frame(self.surface, self.pygame)
            self.pygame.display.flip()
            return

        if self.view == "key_logger":
            self.render_key_logger_view()
            maybe_dump_debug_frame(self.surface, self.pygame)
            self.pygame.display.flip()
            return

        title_text = self.title_for_view()
        title = self.title_font.render(title_text, False, PRIMARY_COLOR)
        title_rect = title.get_rect(topleft=(LEFT_MARGIN, max(36, self.height // 12)))
        self.surface.blit(title, title_rect)

        running = self.proxy_running()
        status_text = self.status_text(running)
        body_bottom = self.render_wrapped_status(status_text, title_rect.bottom + 20)
        if self.view == "support_me":
            body_bottom = self.render_support_description(body_bottom + 16)
        elif self.view in ("support_me_monthly", "support_me_qr"):
            body_bottom = self.render_support_scan_hint(body_bottom + 16)
            if self.view == "support_me_qr":
                body_bottom = self.render_support_qr(body_bottom + 16)

        items = self.current_labels(running)
        start_y = body_bottom + 34
        gap = max(self.item_font.get_height() + 6, self.height // 18)
        self.normalize_selection(items, start_y, gap)
        self.render_game_preview()
        self.render_home_logo()
        self.render_support_monthly_preview(start_y)
        positions = self.item_positions(items, start_y, gap)
        visible_offset, visible_items = self.visible_items(items, positions, start_y)
        scroll_base_y = positions[visible_offset] - start_y if visible_items else 0
        for visible_index, (actual_index, label) in enumerate(visible_items):
            color = (
                SELECTED_COLOR
                if actual_index == self.selected_index
                else self.item_text_color(label)
            )
            prefix = "> " if actual_index == self.selected_index else "  "
            font = self.item_font_for_index(actual_index)
            text = font.render(f"{prefix}{label}", False, color)
            rect = text.get_rect(
                topleft=(LEFT_MARGIN, positions[actual_index] - scroll_base_y)
            )
            self.surface.blit(text, rect)

        if self.message is not None:
            text, expires_at = self.message
            if time.monotonic() >= expires_at:
                self.message = None
            else:
                overlay = self.status_font.render(text, False, SELECTED_COLOR)
                overlay_rect = overlay.get_rect(topleft=(LEFT_MARGIN, self.height - 56))
                self.surface.blit(overlay, overlay_rect)
        else:
            hint = self.bottom_hint_text()
            if hint is not None:
                overlay = self.status_font.render(hint, False, SELECTED_COLOR)
                overlay_rect = overlay.get_rect(topleft=(LEFT_MARGIN, self.height - 56))
                self.surface.blit(overlay, overlay_rect)

        if self.view == "main":
            version = self.meta_font.render(APP_VERSION, False, SECONDARY_TEXT_COLOR)
            version_rect = version.get_rect(
                bottomright=(self.width - LEFT_MARGIN, self.height - 18)
            )
            self.surface.blit(version, version_rect)

        maybe_dump_debug_frame(self.surface, self.pygame)
        self.pygame.display.flip()

    def labels(self, running: bool) -> list[str]:
        if self.view == "controller_calibration":
            return []

        if self.view == "key_logger":
            return []

        if self.view == "cached_games":
            cached = [game.title for game in self.cached_games]
            if getattr(self, "main_online", False):
                return ["Add ROM", "Start Smart Cache", *cached, "Clear cache", "Back"]
            return [*cached, "Clear cache", "Back"]

        if self.view == "pending_awards":
            labels = []
            for award in self.pending_awards:
                labels.extend([award.game_title, award.detail_text])
            labels.append("Back")
            return labels

        if self.view == "pending_award_actions":
            return ["Delete pending award", "Back"]

        if self.view == "smart_cache_prompt":
            return ["Start Smart Cache", "Skip"]

        if self.view == "clear_cache_confirm":
            return ["YES", "NO"]

        if self.view == "cache_progress":
            return ["Back"] if getattr(self, "cache_completed", False) else ["Abort"]

        if self.view == "update_prompt":
            return ["Download and install", "Later"]

        if self.view == "send_logs_confirm":
            return ["YES", "NO"]

        if self.view == "send_logs_progress":
            if self.storage_corruption_active and self.storage_corruption_done:
                return ["Back"]
            return []

        if self.view == "send_logs_result":
            return ["Back"]

        if self.view == "game_actions":
            unlock_titles = self.game_actions_unlock_titles()
            return ["Remove cache", *unlock_titles, "Back"]

        if self.view == "support_me":
            return ["Monthly", "One time", "Back"]

        if self.view == "support_me_monthly":
            return [tier_label for tier_label, _key, _qr in SUPPORT_MONTHLY_TIERS] + ["Back"]

        if self.view == "support_me_qr":
            return ["Back"]

        if self.view == "file_browser":
            if self.browser_dir is None:
                return ["Cancel"]

            labels = []
            if self.browser_has_cacheable_files():
                labels.append("Add folder")
            effective_root = self.browser_root or resolve_rom_root(load_config())
            if self.browser_dir.parent != self.browser_dir and self.browser_dir != effective_root:
                labels.append("..")
            labels.extend(entry.name for entry in self.browser_entries)
            labels.append("Cancel")
            return labels

        self.refresh_main_menu_state()
        service_mode = getattr(self, "main_service_mode", False)
        labels = []
        if not service_mode:
            labels.append("Stop proxy" if running else "Start proxy")
        if self.main_logged_in:
            labels.append(f"Cached games ({len(self.cached_games)})")
        if self.pending_awards:
            labels.append(f"Pending awards ({len(self.pending_awards)})")
        if self.main_autostart_supported and not service_mode:
            labels.append(
                "Disable autostart"
                if self.main_autostart_enabled
                else "Enable autostart"
            )
        if (
            ((self.is_knulli_platform() or running_on_darkos()) and not service_mode)
            or running_on_muos()
            or running_on_rocknix()
        ):
            labels.append("Uninstall")
        labels.append("Support me")
        labels.append("Send Logs")
        if os.environ.get("RAOFFLINEPROXY_DEBUG"):
            labels.append("Key Logger")
        labels.append("Exit Menu")
        return labels

    def is_logged_in(self, config_data: dict | None = None) -> bool:
        if config_data is None:
            self.refresh_main_menu_state()
            return bool(getattr(self, "main_logged_in", False))

        cached_credentials = self.storage.load_login_credentials()
        if cached_credentials is not None:
            return not self.storage.is_token_invalid(cached_credentials["token"])

        cfg_credentials = load_retroarch_credentials(resolve_retroarch_cfg(config_data))
        if cfg_credentials is None:
            return False

        token = cfg_credentials.get("token")
        if token is not None:
            return not self.storage.is_token_invalid(token)
        return True

    def current_labels(self, running: bool | None = None) -> list[str]:
        return self.labels(self.proxy_running() if running is None else running)

    def title_for_view(self) -> str:
        if self.view == "key_logger":
            return "Key Logger"
        if self.view == "controller_calibration":
            return "Controller Setup"
        if self.view == "cached_games":
            return "Cached Games"
        if self.view == "pending_awards":
            return "Pending Awards"
        if self.view == "pending_award_actions":
            return (
                self.active_pending_award.game_title
                if self.active_pending_award is not None
                else "Pending Award"
            )
        if self.view == "game_actions":
            return (
                self.active_game.title
                if self.active_game is not None
                else "Cached Game"
            )
        if self.view == "file_browser":
            return "Add ROM"
        if self.view == "update_prompt":
            return "Update Available"
        if self.view == "clear_cache_confirm":
            return "Clear Cache?"
        if self.view == "cache_progress":
            return self.cache_progress_title or "Caching"
        if self.view == "send_logs_confirm":
            return "Send Logs?"
        if self.view == "send_logs_progress":
            return "Data Reset" if self.storage_corruption_active else "Sending Logs"
        if self.view == "send_logs_result":
            return "Send Logs" if self.log_upload_result and self.log_upload_result[0] else "Send Logs Failed"
        if self.view == "support_me":
            return "Support RAOfflineProxy"
        if self.view == "support_me_monthly":
            return "Choose a Monthly Amount"
        if self.view == "support_me_qr":
            return self.support_qr_display_label()
        return "RAOfflineProxy"

    def support_qr_display_label(self) -> str:
        if self.support_selected_tier == "onetime":
            return "Scan to Donate"
        for tier_label, key, _qr in SUPPORT_MONTHLY_TIERS:
            if key == self.support_selected_tier:
                return f"Scan to Donate {tier_label}"
        return "Scan to Donate"

    def support_qr_path(self) -> Path | None:
        return self.support_qr_path_for_tier(self.support_selected_tier)

    def support_qr_path_for_tier(self, tier_key: str | None) -> Path | None:
        if tier_key == "onetime":
            return SUPPORT_ONETIME_QR
        for _label, key, qr_path in SUPPORT_MONTHLY_TIERS:
            if key == tier_key:
                return qr_path
        return None

    def item_text_color(self, label: str) -> tuple[int, int, int]:
        if label in {"Back", "Cancel", ""}:
            return SECONDARY_TEXT_COLOR
        return TEXT_COLOR

    def item_font_for_index(self, index: int):
        return self.item_font

    def game_actions_unlock_titles(self) -> list[str]:
        if self.active_game is None:
            return []
        if (
            getattr(self, "active_game_unlock_game_id", None)
            != self.active_game.game_id
        ):
            self.refresh_active_game_unlocks()
        return list(getattr(self, "active_game_unlock_titles_cached", []))

    def status_text(self, running: bool) -> str:
        if self.view == "key_logger":
            return "Press any button to log its code"
        if self.view == "controller_calibration":
            if self.calibration_step == "confirm":
                return "Press the button labeled A"
            if self.calibration_step == "cancel":
                return "Press the button labeled B"
            return "Controller setup complete"
        if self.view == "cached_games":
            return f"CACHED: {len(self.cached_games)} / {MAX_CACHED_GAMES}"
        if self.view == "pending_awards":
            return f"PENDING: {len(self.pending_awards)}"
        if self.view == "pending_award_actions":
            return (
                self.active_pending_award.summary_text
                if self.active_pending_award is not None
                else "No pending award selected"
            )
        if self.view == "smart_cache_prompt":
            return f"SMART CACHE: {self.smart_cache_prompt_count} recent games found"
        if self.view == "cache_progress":
            if getattr(self, "cache_completed", False):
                return self.cache_completion_message or "Cache complete"
            return self.cache_progress_text or "Preparing cache..."
        if self.view == "game_actions":
            if self.active_game is None:
                return "No game selected"
            if (
                getattr(self, "active_game_unlock_game_id", None)
                != self.active_game.game_id
            ):
                self.refresh_active_game_unlocks()
            unlock_count = getattr(self, "active_game_unlock_count_cached", None)
            if unlock_count is None:
                return f"GAME ID: {self.active_game.game_id}, UNLOCKS: unknown"
            return f"GAME ID: {self.active_game.game_id}, UNLOCKS: {unlock_count}"
        if self.view == "file_browser":
            return str(self.browser_dir or "No ROM directory")
        if self.view == "update_prompt":
            return (
                f"Version {self.main_update_version} is available."
                if self.main_update_version is not None
                else "A new version is available."
            )
        if self.view == "send_logs_confirm":
            return "Send logs for support?"
        if self.view == "send_logs_progress":
            return self.log_upload_progress_text or "Uploading logs..."
        if self.view == "send_logs_result":
            if self.log_upload_result is None:
                return ""
            success, message = self.log_upload_result
            return f"Support ID: {message}" if success else f"Upload failed: {message}"
        if self.view == "support_me":
            return SUPPORT_SUBTITLE
        if self.view in ("support_me_monthly", "support_me_qr"):
            return ""
        self.refresh_main_menu_state()
        logged_in = bool(getattr(self, "main_logged_in", False))
        proxy_status = "RUNNING" if running else "STOPPED"
        connectivity_status = (
            "ONLINE" if bool(getattr(self, "main_online", False)) else "OFFLINE"
        )
        if getattr(self, "main_service_mode", False):
            status = f"KNULLI SERVICE: {proxy_status} {connectivity_status}"
        else:
            status = f"PROXY: {proxy_status} {connectivity_status}"
        if not logged_in:
            status += ", LOGIN REQUIRED"
        return status

    def bottom_hint_text(self) -> str | None:
        if self.view == "key_logger":
            return f"B/back to exit  |  log: {SDL_LOG_PATH}"

        if self.view == "controller_calibration":
            if self.calibration_step == "confirm":
                return "Face buttons only. Press A to continue."
            if self.calibration_step == "cancel":
                return "Now press B."
            return None

        if self.view != "main":
            if self.view == "smart_cache_prompt":
                return None
            if self.view == "clear_cache_confirm":
                return self.confirm_cancel_hint("confirm", "cancel")
            if self.view == "cache_progress":
                return None
            if self.view == "update_prompt":
                return self.confirm_cancel_hint("install", None)
            if self.view == "send_logs_confirm":
                return self.confirm_cancel_hint("confirm", "cancel")
            if self.view == "send_logs_progress":
                if self.storage_corruption_active and self.storage_corruption_done:
                    return self.confirm_cancel_hint("dismiss", None)
                return None
            if self.view == "send_logs_result":
                return self.confirm_cancel_hint("dismiss", None)
            if self.view == "support_me_qr":
                return None
            if self.view == "file_browser" and self.browser_at_switchable_root():
                alt = resolve_rom_root(load_config()) if self.browser_root == MUOS_SDCARD_ROOT else MUOS_SDCARD_ROOT
                return f"L/R: switch to {alt}"
            cache_result = getattr(self, "cache_result", None)
            if cache_result is not None:
                text, expires_at = cache_result
                if time.monotonic() >= expires_at:
                    self.finish_cache_progress()
                    return None
                return text
            return getattr(self, "smart_cache_progress_text", None)

        if (
            getattr(self, "smart_cache_in_progress", False)
            and getattr(self, "smart_cache_progress_text", None) is not None
        ):
            return self.smart_cache_progress_text

        smart_cache_result = getattr(self, "smart_cache_result", None)
        if smart_cache_result is not None:
            text, expires_at = smart_cache_result
            if time.monotonic() >= expires_at:
                self.smart_cache_result = None
            else:
                return text

        if self.is_logged_in():
            return None

        return "Login to RetroAchievements in system settings."

    def handle_events(self) -> None:
        # Onion's vendored SDL2 build runs a generic Linux evdev keyboard
        # backend independent of its video driver, so the same physical
        # press arrives here as KEYDOWN *and* via handle_raw_input reading
        # the device directly, double-firing navigation. This is confirmed
        # on Onion specifically (verified with a dual-logging capture that
        # showed both a "RAW" and an "SDL KEYDOWN" line ~20ms apart for one
        # tap) — it is NOT known to happen on muOS/Knulli/ROCKNIX, so the
        # skip is scoped to that hardware rather than applied whenever raw
        # input happens to be available, to avoid silently disabling their
        # existing KEYDOWN path on unverified assumptions. The Miyoo gpio-keys
        # boards are exactly the ones running the Mini SDL2 driver; spruce's
        # aarch64 boards are not, and their button codes are unverified, so
        # leaving KEYDOWN live there is the safer default. Keep draining the
        # event queue regardless (QUIT still matters, and an undrained SDL
        # event queue can back up).
        skip_keydown = running_on_mini_sdl_stack() and bool(getattr(self, "input_handles", None))
        for event in self.pygame.event.get():
            if event.type == self.pygame.QUIT:
                self.running = False
                return

            if event.type == self.pygame.KEYDOWN:
                if self.view == "unsupported_onion":
                    self.running = False
                    return
                if not skip_keydown:
                    self.handle_key(event.key)
                continue

    def handle_raw_input(self) -> None:
        for key in read_keys(self.input_handles, self.last_key_press):
            if self.view == "unsupported_onion":
                self.running = False
                return

            if self.handle_calibration_key(key):
                continue

            if self.view == "key_logger":
                self.handle_key_logger_input(key)
                continue

            if key in {KEY_UP, KEY_LEFT, BTN_DPAD_UP, BTN_DPAD_LEFT}:
                self.navigate(-1)
                continue

            if key in {KEY_DOWN, KEY_RIGHT, BTN_DPAD_DOWN, BTN_DPAD_RIGHT}:
                self.navigate(1)
                continue

            if key in {BTN_TL, BTN_TR}:
                if self.browser_at_switchable_root():
                    self.toggle_browser_root()
                continue

            if self.is_confirm_key(key):
                self.activate_selected()
                continue

            if self.is_cancel_key(key):
                self.go_back()

    def handle_key(self, key: int) -> None:
        if self.view == "controller_calibration":
            return

        if key in {self.pygame.K_UP, self.pygame.K_LEFT}:
            self.navigate(-1)
            return
        if key in {self.pygame.K_DOWN, self.pygame.K_RIGHT}:
            self.navigate(1)
            return
        if key in {self.pygame.K_RETURN, self.pygame.K_SPACE, self.pygame.K_s}:
            self.activate_selected()
            return
        if key in {self.pygame.K_ESCAPE, self.pygame.K_BACKSPACE, self.pygame.K_q}:
            self.go_back()

    def navigate(self, delta: int) -> None:
        items = self.current_labels()
        item_count = max(1, len(items))
        self.selected_index = (self.selected_index + delta) % item_count
        start_y = self.item_start_y()
        gap = self.item_gap()
        self.ensure_selection_visible(items, start_y, gap)

    def activate_selected(self) -> None:
        if self.view == "controller_calibration":
            return

        if self.view == "cached_games":
            self.activate_cached_games_selected()
            return

        if self.view == "pending_awards":
            self.activate_pending_awards_selected()
            return

        if self.view == "pending_award_actions":
            self.activate_pending_award_actions_selected()
            return

        if self.view == "smart_cache_prompt":
            self.activate_smart_cache_prompt_selected()
            return

        if self.view == "clear_cache_confirm":
            self.activate_clear_cache_confirm_selected()
            return

        if self.view == "update_prompt":
            self.activate_update_prompt_selected()
            return

        if self.view == "send_logs_confirm":
            self.activate_send_logs_confirm_selected()
            return

        if self.view == "send_logs_progress":
            if self.storage_corruption_active and self.storage_corruption_done:
                self.dismiss_storage_corruption_progress()
            return

        if self.view == "send_logs_result":
            self.dismiss_send_logs_result()
            return

        if self.view == "game_actions":
            self.activate_game_actions_selected()
            return

        if self.view == "file_browser":
            self.activate_file_browser_selected()
            return

        if self.view == "support_me":
            self.activate_support_me_selected()
            return

        if self.view == "support_me_monthly":
            self.activate_support_me_monthly_selected()
            return

        if self.view == "support_me_qr":
            self.dismiss_support_me_qr()
            return

        if self.view == "cache_progress":
            if self.selected_index == 0:
                if getattr(self, "cache_completed", False):
                    self.finish_cache_progress()
                else:
                    self.abort_cache_progress()
            return

        labels = self.current_labels()
        selected_label = labels[self.selected_index] if labels else ""
        if selected_label.startswith(("Start proxy", "Stop proxy")):
            if self.proxy_running():
                self.stop_proxy()
            else:
                self.start_proxy()
            return

        config_data = getattr(self, "config_data", {})
        if selected_label.startswith(("Enable autostart", "Disable autostart")):
            self.toggle_autostart(config_data)
            return

        if selected_label.startswith("Cached games"):
            self.save_view_position("main")
            self.view = "cached_games"
            self.restore_view_position("cached_games")
            self.refresh_cached_games()
            return

        if selected_label.startswith("Pending awards ("):
            self.save_view_position("main")
            self.view = "pending_awards"
            self.restore_view_position("pending_awards")
            self.refresh_pending_awards()
            return

        if selected_label == "Uninstall":
            self.uninstall()
            return

        if selected_label == "Send Logs":
            self.activate_send_logs_confirm()
            return

        if selected_label == "Key Logger":
            self.save_view_position("main")
            self.key_log = []
            self.view = "key_logger"
            self.reset_selection()
            return

        if selected_label == "Support me":
            self.save_view_position("main")
            self.view = "support_me"
            self.restore_view_position("support_me")
            return

        self.running = False

    def activate_support_me_selected(self) -> None:
        labels = self.current_labels()
        selected_label = labels[self.selected_index] if labels else ""

        if selected_label == "Monthly":
            self.save_view_position("support_me")
            self.view = "support_me_monthly"
            self.restore_view_position("support_me_monthly")
            return

        if selected_label == "One time":
            self.save_view_position("support_me")
            self.support_selected_tier = "onetime"
            self.support_qr_return_view = "support_me"
            self.view = "support_me_qr"
            self.reset_selection()
            return

        if selected_label == "Back":
            self.save_view_position("support_me")
            self.view = "main"
            self.restore_view_position("main")
            return

    def activate_support_me_monthly_selected(self) -> None:
        labels = self.current_labels()
        selected_label = labels[self.selected_index] if labels else ""

        if selected_label == "Back":
            self.save_view_position("support_me_monthly")
            self.view = "support_me"
            self.restore_view_position("support_me")
            return

        for tier_label, key, _qr in SUPPORT_MONTHLY_TIERS:
            if selected_label == tier_label:
                self.save_view_position("support_me_monthly")
                self.support_selected_tier = key
                self.support_qr_return_view = "support_me_monthly"
                self.view = "support_me_qr"
                self.reset_selection()
                return

    def dismiss_support_me_qr(self) -> None:
        self.support_selected_tier = None
        self.view = self.support_qr_return_view
        self.restore_view_position(self.support_qr_return_view)

    def cached_games_header_count(self) -> int:
        return 2 if getattr(self, "main_online", False) else 0

    def activate_cached_games_selected(self) -> None:
        labels = self.current_labels()
        selected_label = labels[self.selected_index] if labels else ""

        if selected_label == "Add ROM":
            self.open_file_browser()
            return

        if selected_label == "Start Smart Cache":
            self.start_smart_cache()
            return

        if selected_label == "Clear cache":
            self.save_view_position("cached_games")
            self.clear_cache_return_view = "cached_games"
            self.view = "clear_cache_confirm"
            self.reset_selection()
            return

        if selected_label == "Back":
            self.save_view_position("cached_games")
            self.view = "main"
            self.restore_view_position("main")
            return

        game_index = self.selected_index - self.cached_games_header_count()
        if 0 <= game_index < len(self.cached_games):
            self.save_view_position("cached_games")
            self.active_game = self.cached_games[game_index]
            self.refresh_active_game_unlocks()
            self.view = "game_actions"
            self.reset_selection()
            return

    def activate_pending_awards_selected(self) -> None:
        back_index = len(self.pending_awards) * 2
        if self.selected_index == back_index:
            self.save_view_position("pending_awards")
            self.view = "main"
            self.restore_view_position("main")
            return

        award_index = self.selected_index // 2
        if 0 <= award_index < len(self.pending_awards):
            self.save_view_position("pending_awards")
            self.active_pending_award = self.pending_awards[award_index]
            self.view = "pending_award_actions"
            self.reset_selection()

    def activate_pending_award_actions_selected(self) -> None:
        if self.active_pending_award is None:
            self.view = "pending_awards"
            self.restore_view_position("pending_awards")
            self.refresh_pending_awards()
            return

        if self.selected_index == 0:
            delete_pending_award(self.storage, self.active_pending_award.achievement_id)
            removed_title = self.active_pending_award.achievement_title
            self.active_pending_award = None
            self.refresh_pending_awards()
            self.view = "pending_awards"
            self.restore_view_position("pending_awards")
            self.message = (f"Removed {removed_title}", time.monotonic() + 1.5)
            return

        self.active_pending_award = None
        self.view = "pending_awards"
        self.restore_view_position("pending_awards")

    def activate_smart_cache_prompt_selected(self) -> None:
        if self.selected_index == 0:
            self.start_smart_cache()
            return

        self.dismiss_smart_cache_prompt()

    def activate_clear_cache_confirm_selected(self) -> None:
        if self.selected_index == 0:
            self.clear_cache_and_return()
            return

        self.view = self.clear_cache_return_view
        self.restore_view_position(self.clear_cache_return_view)
        if self.view == "cached_games":
            self.refresh_cached_games()

    def clear_cache_and_return(self) -> None:
        clear_cached_games(self.storage)
        self.active_game = None
        self.refresh_cached_games()
        self.view = self.clear_cache_return_view
        self.restore_view_position(self.clear_cache_return_view)
        self.message = ("Cache cleared", time.monotonic() + 1.5)

    def is_knulli_platform(self) -> bool:
        return Path("/userdata/system").exists()

    def update_platform(self) -> str | None:
        """The release channel to check for updates, or None where there is none.

        None is a normal state, not a failure: it must not be signalled by returning a
        platform name that `update.validate_platform()` rejects, because every caller
        would then log a spurious "update check failed" line on each refresh.
        """
        if running_on_muos():
            return "muos"
        if running_on_spruce():
            return "spruce"
        if running_on_onion():
            return "onion"
        if running_on_allium():
            return "allium"
        if running_on_rocknix():
            return "rocknix"
        if running_on_darkos():
            return "darkos"
        return "knulli"

    def calibration_complete(self) -> bool:
        return (
            self.configured_confirm_button() is not None
            and self.configured_cancel_button() is not None
        )

    def needs_controller_calibration(self) -> bool:
        return not self.calibration_complete()

    def configured_confirm_button(self) -> int | None:
        value = self.config_data.get("controller_confirm_button")
        return self.parse_button_code(value)

    def configured_cancel_button(self) -> int | None:
        value = self.config_data.get("controller_cancel_button")
        return self.parse_button_code(value)

    def parse_button_code(self, value: object) -> int | None:
        if value is None:
            return None

        try:
            return int(value)
        except (TypeError, ValueError):
            return None

    def handle_calibration_key(self, key: int) -> bool:
        if self.view != "controller_calibration":
            return False

        if key in CALIBRATION_EXCLUDED_KEYS:
            return True

        if self.calibration_step == "confirm":
            self.calibration_confirm_button = key
            self.calibration_step = "cancel"
            self.persist_controller_mapping()
            return True

        if self.calibration_step != "cancel":
            return True

        if key == self.calibration_confirm_button:
            self.message = ("B must be a different button", time.monotonic() + 1.5)
            return True

        self.calibration_cancel_button = key
        self.calibration_step = "done"
        self.persist_controller_mapping()
        self.view = "main"
        self.message = ("Controller mapping saved", time.monotonic() + 1.5)
        self.refresh_main_menu_state(force=True)
        return True

    def persist_controller_mapping(self) -> None:
        self.config_data["controller_confirm_button"] = self.calibration_confirm_button
        if self.calibration_cancel_button is None:
            self.config_data.pop("controller_cancel_button", None)
        else:
            self.config_data["controller_cancel_button"] = self.calibration_cancel_button
        save_config(self.config_data)

    def confirm_button_name(self) -> str:
        return "A"

    def cancel_button_name(self) -> str:
        return "B"

    def confirm_cancel_hint(self, confirm_action: str, cancel_action: str | None) -> str:
        confirm_label = self.confirm_button_name()
        if cancel_action is None:
            return f"Press {confirm_label} to {confirm_action}."

        cancel_label = self.cancel_button_name()
        return (
            f"Press {confirm_label} to {confirm_action}. "
            f"{cancel_label} to {cancel_action}."
        )

    def is_confirm_key(self, key: int) -> bool:
        confirm_key = self.calibration_confirm_button or BTN_SOUTH
        return key in {KEY_ENTER, KEY_SPACE, KEY_S, confirm_key, BTN_START}

    def is_cancel_key(self, key: int) -> bool:
        cancel_key = self.calibration_cancel_button or BTN_EAST
        return key in {KEY_ESC, KEY_BACKSPACE, KEY_Q, cancel_key, BTN_SELECT}

    def activate_game_actions_selected(self) -> None:
        if self.active_game is None:
            self.view = "cached_games"
            self.restore_view_position("cached_games")
            self.refresh_cached_games()
            return

        if self.selected_index == 0:
            remove_cached_game(self.storage, self.active_game.game_id)
            removed_title = self.active_game.title
            self.active_game = None
            self.clear_active_game_unlocks()
            self.refresh_cached_games()
            self.view = "cached_games"
            self.restore_view_position("cached_games")
            self.message = (f"Removed {removed_title}", time.monotonic() + 1.5)
            return

        if self.selected_index == len(self.game_actions_unlock_titles()) + 1:
            self.active_game = None
            self.clear_active_game_unlocks()
            self.view = "cached_games"
            self.restore_view_position("cached_games")

    def activate_file_browser_selected(self) -> None:
        if self.browser_dir is None:
            self.view = "cached_games"
            self.reset_selection()
            return

        effective_root = self.browser_root or resolve_rom_root(load_config())
        has_add_folder = self.browser_has_cacheable_files()
        has_parent = (
            self.browser_dir.parent != self.browser_dir and self.browser_dir != effective_root
        )
        first_entry_index = 1 if has_add_folder else 0
        parent_index = first_entry_index if has_parent else None
        if has_parent:
            first_entry_index += 1
        cancel_index = first_entry_index + len(self.browser_entries)
        if has_add_folder and self.selected_index == 0:
            self.start_folder_cache_for_browser_dir()
            return
        if parent_index is not None and self.selected_index == parent_index:
            self.save_browser_position()
            self.set_browser_dir(self.browser_dir.parent, restore=True)
            return
        if self.selected_index == cancel_index:
            self.save_browser_position()
            self.view = "cached_games"
            self.restore_view_position("cached_games")
            self.refresh_cached_games()
            return

        entry = self.browser_entries[self.selected_index - first_entry_index]
        if entry.is_dir():
            self.save_browser_position()
            self.set_browser_dir(entry, restore=True)
            return

        self.start_single_rom_cache(entry)

    def open_file_browser(self) -> None:
        try:
            self.save_view_position("cached_games")
            root = resolve_rom_root(load_config())
            self.browser_root = root
            self.set_browser_dir(root, restore=True)
            self.view = "file_browser"
        except Exception as exc:
            self.message = (f"Browse failed: {exc}", time.monotonic() + ERROR_SECONDS)

    def handle_key_logger_input(self, key: int) -> None:
        name = KEY_NAMES.get(key, "unknown")
        entry = f"{key}  0x{key:03X}  {name}"
        self.key_log.append(key)
        if len(self.key_log) > 10:
            self.key_log = self.key_log[-10:]
        log_menu_sdl(f"key_logger {entry}")
        if self.is_cancel_key(key):
            self.view = "main"
            self.restore_view_position("main")

    def render_unsupported_onion_view(self) -> None:
        title = self.title_font.render("Unsupported Onion version", False, ERROR_COLOR)
        title_rect = title.get_rect(topleft=(LEFT_MARGIN, max(36, self.height // 12)))
        self.surface.blit(title, title_rect)

        detected = onion_os_version() or "unknown"
        message = (
            f"This OnionOS build ({detected}) is not supported.\n"
            f"RAOfflineProxy requires Onion {SUPPORTED_ONION_VERSION_PREFIX} or newer — "
            "older builds ship a RetroArch achievements client that is not reliably "
            "compatible with a custom host.\n"
            "All functionality is disabled until Onion is updated."
        )
        body_bottom = self.render_wrapped_status(message, title_rect.bottom + 20)

        hint = self.status_font.render("Press any key to exit", False, SELECTED_COLOR)
        self.surface.blit(hint, hint.get_rect(topleft=(LEFT_MARGIN, body_bottom + 20)))

    def render_key_logger_view(self) -> None:
        title_text = self.title_for_view()
        title = self.title_font.render(title_text, False, PRIMARY_COLOR)
        title_rect = title.get_rect(topleft=(LEFT_MARGIN, max(36, self.height // 12)))
        self.surface.blit(title, title_rect)

        status_bottom = self.render_wrapped_status(self.status_text(False), title_rect.bottom + 20)

        gap = max(self.item_font.get_height() + 6, self.height // 18)
        y = status_bottom + 34
        for key in self.key_log:
            name = KEY_NAMES.get(key, "unknown")
            line = f"  {key}  0x{key:03X}  {name}"
            rendered = self.item_font.render(line, False, TEXT_COLOR)
            self.surface.blit(rendered, rendered.get_rect(topleft=(LEFT_MARGIN, y)))
            y += gap

        hint = self.bottom_hint_text()
        if hint is not None:
            overlay = self.status_font.render(hint, False, SELECTED_COLOR)
            self.surface.blit(overlay, overlay.get_rect(topleft=(LEFT_MARGIN, self.height - 56)))

    def browser_at_switchable_root(self) -> bool:
        if not running_on_muos():
            return False
        if self.view != "file_browser" or self.browser_dir is None or self.browser_root is None:
            return False
        if self.browser_dir != self.browser_root:
            return False
        if MUOS_SDCARD_ROOT == self.browser_root:
            return resolve_rom_root(load_config()).exists()
        return MUOS_SDCARD_ROOT.exists()

    def toggle_browser_root(self) -> None:
        if not self.browser_at_switchable_root():
            return
        current_root = self.browser_root
        if current_root == MUOS_SDCARD_ROOT:
            new_root = resolve_rom_root(load_config())
        else:
            new_root = MUOS_SDCARD_ROOT
        if not new_root.exists():
            self.message = (f"Not found: {new_root}", time.monotonic() + ERROR_SECONDS)
            return
        self.save_browser_position()
        self.browser_root = new_root
        self.set_browser_dir(new_root, restore=False)

    def set_browser_dir(self, path: Path, restore: bool = False) -> None:
        self.browser_dir = path
        self.browser_entries = list_browser_entries(path)
        if restore:
            self.restore_browser_position(path)
            return
        self.reset_selection()

    def refresh_cached_games(self) -> None:
        self.cached_games = list_cached_games(self.storage)
        self.pending_awards = list_pending_awards(self.storage)
        self.preview_surface = None
        self.preview_game_id = None
        self.achievement_preview_surface = None
        self.achievement_preview_game_id = None
        self.achievement_preview_title = None

    def refresh_pending_awards(self) -> None:
        self.pending_awards = list_pending_awards(self.storage)

    def browser_has_cacheable_files(self) -> bool:
        if self.browser_dir is None:
            return False
        return directory_has_supported_roms(self.browser_dir)

    def start_single_rom_cache(self, path: Path) -> None:
        self.save_browser_position()
        self.cache_progress_title = f"Caching: {path.name}"
        self.cache_progress_text = "Preparing cache..."
        self.cache_result = None
        self.cache_abort_requested = False
        self.cache_completed = False
        self.cache_completion_message = None
        self.cache_return_view = "file_browser"
        self.cache_return_browser_dir = self.browser_dir
        self.cache_return_browser_restore = True
        self.view = "cache_progress"

        def worker() -> None:
            try:
                result = add_rom_to_cache(path, self.storage, load_config())
                aborted = self.cache_abort_requested
                self.cache_result = (result.message, time.monotonic() + 1.5)
                self.cache_completion_message = (
                    "Aborted: scanned 1, cached 1, skipped 0"
                    if aborted and result.success
                    else result.message
                    if not result.success
                    else "Aborted: scanned 1, cached 0, skipped 1"
                    if aborted
                    else "Scanned 1, cached 1, skipped 0"
                    if result.success
                    else "Scanned 1, cached 0, skipped 1"
                )
                self.cache_completed = True
            except Exception as exc:
                self.cache_result = (
                    f"Cache failed: {exc}",
                    time.monotonic() + ERROR_SECONDS,
                )
                self.cache_completion_message = f"Cache failed: {exc}"
                self.cache_completed = True
            finally:
                if self.view == "cache_progress":
                    self.cache_progress_text = None

        self.cache_worker_thread = threading.Thread(target=worker, daemon=True)
        self.cache_worker_thread.start()

    def start_folder_cache_for_browser_dir(self) -> None:
        if self.browser_dir is None:
            return

        current_dir = self.browser_dir
        cache_paths = list_scannable_files_recursive(current_dir)
        self.save_browser_position()
        self.cache_progress_title = f"Caching: {current_dir.name}"
        if cache_paths:
            self.cache_progress_text = (
                f"Caching 1/{len(cache_paths)}: {cache_paths[0].name}"
            )
        else:
            self.cache_progress_text = "Preparing cache..."
        self.cache_result = None
        self.cache_abort_requested = False
        self.cache_completed = False
        self.cache_completion_message = None
        self.cache_return_view = "cached_games"
        self.cache_return_browser_dir = current_dir
        self.cache_return_browser_restore = False
        self.view = "cache_progress"

        def worker() -> None:
            try:
                result = run_folder_cache(
                    self.storage,
                    load_config(),
                    current_dir,
                    paths=cache_paths,
                    should_abort=lambda: self.cache_abort_requested,
                    on_progress=self.update_cache_progress,
                )
                if result.total <= 0:
                    self.cache_result = (
                        "No ROM files in this folder",
                        time.monotonic() + ERROR_SECONDS,
                    )
                    self.cache_completion_message = (
                        "Aborted: scanned 0, cached 0, skipped 0"
                        if self.cache_abort_requested
                        else "Scanned 0, cached 0, skipped 0"
                    )
                    self.cache_completed = True
                else:
                    self.cache_result = (
                        f"Folder cache complete: {result.cached} / {result.total}",
                        time.monotonic() + 1.5,
                    )
                    self.cache_completion_message = (
                        f"Aborted: scanned {result.scanned}, cached {result.cached}, skipped {result.skipped}"
                        if self.cache_abort_requested
                        else f"Scanned {result.scanned}, cached {result.cached}, skipped {result.skipped}"
                    )
                    self.cache_completed = True
            except Exception as exc:
                self.cache_result = (
                    f"Folder cache failed: {exc}",
                    time.monotonic() + ERROR_SECONDS,
                )
                self.cache_completion_message = f"Folder cache failed: {exc}"
                self.cache_completed = True
            finally:
                if self.view == "cache_progress":
                    self.cache_progress_text = None

        self.cache_worker_thread = threading.Thread(target=worker, daemon=True)
        self.cache_worker_thread.start()

    def update_cache_progress(self, progress) -> None:
        self.cache_progress_text = (
            f"Caching {progress.scanned}/{progress.total}: {progress.current_label}"
        )

    def finish_cache_progress(self) -> None:
        return_view = self.cache_return_view
        return_browser_dir = self.cache_return_browser_dir
        return_browser_restore = self.cache_return_browser_restore
        self.cache_result = None
        self.cache_progress_text = None
        self.cache_progress_title = None
        self.cache_abort_requested = False
        self.cache_completed = False
        self.cache_completion_message = None
        self.cache_return_view = "cached_games"
        self.cache_return_browser_dir = None
        self.cache_return_browser_restore = False
        self.refresh_cached_games()
        if return_view == "file_browser" and return_browser_dir is not None:
            self.view = "file_browser"
            self.set_browser_dir(return_browser_dir, restore=return_browser_restore)
            return
        if return_view == "main":
            self.view = "main"
            self.refresh_main_menu_state(force=True)
            self.restore_view_position("main")
            return
        self.view = "cached_games"
        self.restore_view_position("cached_games")

    def abort_cache_progress(self) -> None:
        if self.cache_completed:
            self.finish_cache_progress()
            return

        self.cache_abort_requested = True
        self.cache_progress_text = "Aborting..."

    def go_back(self) -> None:
        if self.view == "key_logger":
            self.view = "main"
            self.restore_view_position("main")
            return

        if self.view == "file_browser":
            if self.browser_dir is None:
                self.view = "cached_games"
                self.restore_view_position("cached_games")
                self.refresh_cached_games()
                return

            effective_root = self.browser_root or resolve_rom_root(load_config())
            if self.browser_dir == effective_root:
                self.save_browser_position()
                self.view = "cached_games"
                self.restore_view_position("cached_games")
                self.refresh_cached_games()
                return

            if self.browser_dir.parent != self.browser_dir:
                self.save_browser_position()
                self.set_browser_dir(self.browser_dir.parent, restore=True)
                return

            self.view = "cached_games"
            self.restore_view_position("cached_games")
            self.refresh_cached_games()
            return

        if self.view == "cached_games":
            self.save_view_position("cached_games")
            self.view = "main"
            self.refresh_main_menu_state(force=True)
            self.restore_view_position("main")
            return

        if self.view == "pending_awards":
            self.save_view_position("pending_awards")
            self.view = "main"
            self.refresh_main_menu_state(force=True)
            self.restore_view_position("main")
            return

        if self.view == "smart_cache_prompt":
            self.dismiss_smart_cache_prompt()
            return

        if self.view == "clear_cache_confirm":
            self.view = self.clear_cache_return_view
            self.restore_view_position(self.clear_cache_return_view)
            if self.view == "cached_games":
                self.refresh_cached_games()
            return

        if self.view == "update_prompt":
            self.dismiss_update_prompt()
            return

        if self.view == "cache_progress":
            return

        if self.view == "send_logs_confirm":
            self.view = "main"
            self.restore_view_position("main")
            return

        if self.view == "send_logs_progress":
            if self.storage_corruption_active and self.storage_corruption_done:
                self.dismiss_storage_corruption_progress()
            return

        if self.view == "send_logs_result":
            self.dismiss_send_logs_result()
            return

        if self.view == "pending_award_actions":
            self.active_pending_award = None
            self.view = "pending_awards"
            self.restore_view_position("pending_awards")
            return

        if self.view == "game_actions":
            self.active_game = None
            self.clear_active_game_unlocks()
            self.view = "cached_games"
            self.restore_view_position("cached_games")
            return

        if self.view == "support_me":
            self.save_view_position("support_me")
            self.view = "main"
            self.restore_view_position("main")
            return

        if self.view == "support_me_monthly":
            self.save_view_position("support_me_monthly")
            self.view = "support_me"
            self.restore_view_position("support_me")
            return

        if self.view == "support_me_qr":
            self.dismiss_support_me_qr()
            return

        self.running = False

    def render_game_preview(self) -> None:
        game = self.preview_target_game()
        if game is None:
            self.preview_surface = None
            self.preview_game_id = None
            self.achievement_preview_surface = None
            self.achievement_preview_game_id = None
            self.achievement_preview_title = None
            return

        if (
            self.preview_game_id != game.game_id or self.preview_surface is None
        ) and self.should_load_preview(game.game_id):
            self.preview_surface = self.load_game_preview_surface(game)
            self.preview_game_id = (
                game.game_id if self.preview_surface is not None else None
            )
            self.preview_failed_game_id = (
                game.game_id if self.preview_surface is None else None
            )
            self.preview_failed_at = time.monotonic()

        if self.preview_surface is None:
            return

        preview_rect = self.preview_surface.get_rect(topright=(self.width - 24, 24))
        self.surface.blit(self.preview_surface, preview_rect)

        achievement_surface = self.current_achievement_preview_surface()
        if achievement_surface is None:
            return

        award_rect = achievement_surface.get_rect(
            right=preview_rect.left - 16,
            centery=preview_rect.centery,
        )
        self.surface.blit(achievement_surface, award_rect)

    def should_load_preview(self, game_id: int) -> bool:
        if getattr(self, "preview_failed_game_id", None) != game_id:
            return True
        elapsed = time.monotonic() - getattr(self, "preview_failed_at", 0.0)
        return elapsed >= PREVIEW_RETRY_SECONDS

    def render_home_logo(self) -> None:
        if self.view != "main":
            return

        if self.logo_surface is None:
            self.logo_surface = self.load_logo_surface()

        if self.logo_surface is None:
            return

        logo_rect = self.logo_surface.get_rect(topright=(self.width - 24, 24))
        self.surface.blit(self.logo_surface, logo_rect)

    def preview_target_game(self):
        if self.view == "cached_games":
            game_index = self.selected_index - self.cached_games_header_count()
            if 0 <= game_index < len(self.cached_games):
                return self.cached_games[game_index]
            return None

        if (
            self.view == "pending_award_actions"
            and self.active_pending_award is not None
        ):
            game_id = self.active_pending_award.game_id
            if game_id is None:
                return None
            for game in self.cached_games:
                if game.game_id == game_id:
                    return game
            return None

        if self.view == "game_actions":
            return self.active_game

        return None

    def load_game_preview_surface(self, game):
        try:
            preview_path = ensure_game_preview(game, self.storage, load_config())
            if preview_path is None:
                return None

            image = self.pygame.image.load(str(preview_path))
            image = (
                image.convert_alpha()
                if image.get_alpha() is not None
                else image.convert()
            )
            scaled_size = self.fit_preview_size(image.get_width(), image.get_height())
            return self.pygame.transform.smoothscale(image, scaled_size)
        except Exception as exc:
            log_menu_sdl(f"preview load failed gameId={game.game_id} error={exc}")
            return None

    def load_logo_surface(self):
        try:
            if not LOGO_PATH.exists():
                return None

            image = self.pygame.image.load(str(LOGO_PATH))
            image = (
                image.convert_alpha()
                if image.get_alpha() is not None
                else image.convert()
            )
            scaled_size = self.fit_preview_size(image.get_width(), image.get_height())
            return self.pygame.transform.smoothscale(image, scaled_size)
        except Exception as exc:
            log_menu_sdl(f"logo load failed path={LOGO_PATH} error={exc}")
            return None

    def current_achievement_preview_surface(self):
        if self.view != "game_actions" or self.active_game is None:
            self.achievement_preview_surface = None
            self.achievement_preview_game_id = None
            self.achievement_preview_title = None
            return None

        unlock_index = self.selected_index - 1
        unlock_titles = self.game_actions_unlock_titles()
        if unlock_index < 0 or unlock_index >= len(unlock_titles):
            self.achievement_preview_surface = None
            self.achievement_preview_game_id = None
            self.achievement_preview_title = None
            return None

        title = unlock_titles[unlock_index]
        if (
            self.achievement_preview_surface is not None
            and self.achievement_preview_game_id == self.active_game.game_id
            and self.achievement_preview_title == title
        ):
            return self.achievement_preview_surface

        self.achievement_preview_surface = self.load_achievement_preview_surface(
            self.active_game.game_id, title
        )
        self.achievement_preview_game_id = self.active_game.game_id
        self.achievement_preview_title = title
        return self.achievement_preview_surface

    def load_achievement_preview_surface(self, game_id: int, title: str):
        if title in self._badge_surface_cache:
            return self._badge_surface_cache[title]

        try:
            badge_path = self._badge_path_cache.get(title)
            if badge_path is None:
                self._badge_surface_cache[title] = None
                return None

            image = self.pygame.image.load(str(badge_path))
            image = (
                image.convert_alpha()
                if image.get_alpha() is not None
                else image.convert()
            )
            scaled_size = self.fit_achievement_preview_size(
                image.get_width(), image.get_height()
            )
            surface = self.pygame.transform.smoothscale(image, scaled_size)
            self._badge_surface_cache[title] = surface
            return surface
        except Exception as exc:
            log_menu_sdl(
                f"achievement preview load failed gameId={game_id} title={title} error={exc}"
            )
            return None

    def fit_achievement_preview_size(self, width: int, height: int) -> tuple[int, int]:
        # RA badges are small source images (commonly 64px); cap the upscale
        # factor rather than 1.0 so they still fill their box on large screens
        # instead of staying pinned to native size while everything else scales.
        max_width = max(64, self.width // 8)
        max_height = max(64, self.height // 6)
        scale = min(max_width / max(1, width), max_height / max(1, height), 4.0)
        return max(1, int(width * scale)), max(1, int(height * scale))

    def fit_preview_size(self, width: int, height: int) -> tuple[int, int]:
        max_width = max(96, self.width // 4)
        max_height = max(96, self.height // 3)
        scale = min(max_width / max(1, width), max_height / max(1, height), 4.0)
        return max(1, int(width * scale)), max(1, int(height * scale))

    def wrap_text_to_width(self, text: str, font, max_width: int) -> list[str]:
        # Word-wrap measured in actual rendered pixel width rather than character
        # count, since these fonts aren't monospace — a char-count wrap either
        # overflows or wastes space depending on the word mix.
        words = text.split()
        lines: list[str] = []
        current = ""
        for word in words:
            candidate = f"{current} {word}".strip()
            if not current or font.size(candidate)[0] <= max_width:
                current = candidate
            else:
                lines.append(current)
                current = word
        if current:
            lines.append(current)
        return lines

    def render_wrapped_status(self, text: str, top_y: int) -> int:
        # Each "\n"-separated segment forces its own line (e.g. one sentence
        # per line for the storage-corruption notice); word-wrap only kicks
        # in within a segment that's still too wide for the screen on its own.
        max_width = self.width - (2 * LEFT_MARGIN)
        segments = text.split("\n") if text else [""]
        lines = [
            line
            for segment in segments
            for line in (self.wrap_text_to_width(segment, self.status_font, max_width) or [""])
        ]
        bottom = top_y
        y = top_y
        for line in lines:
            surface = self.status_font.render(line, False, STATUS_COLOR)
            rect = surface.get_rect(topleft=(LEFT_MARGIN, y))
            self.surface.blit(surface, rect)
            bottom = rect.bottom
            y = rect.bottom + 4
        return bottom

    def render_support_description(self, top_y: int) -> int:
        max_width = self.width - (2 * LEFT_MARGIN)
        y = top_y
        for line in self.wrap_text_to_width(SUPPORT_DESCRIPTION, self.status_font, max_width):
            surface = self.status_font.render(line, False, TEXT_COLOR)
            rect = surface.get_rect(topleft=(LEFT_MARGIN, y))
            self.surface.blit(surface, rect)
            y = rect.bottom + 4
        return y

    def render_support_scan_hint(self, top_y: int) -> int:
        # Wrapped rather than a single status-bar line, since combining "scan"
        # and the fallback URL into one message can easily run past screen
        # width on smaller handhelds.
        max_width = self.width - (2 * LEFT_MARGIN)
        text = f"Scan with your phone's camera, or visit {SUPPORT_DONATE_URL}"
        y = top_y
        for line in self.wrap_text_to_width(text, self.meta_font, max_width):
            surface = self.meta_font.render(line, False, SECONDARY_TEXT_COLOR)
            rect = surface.get_rect(topleft=(LEFT_MARGIN, y))
            self.surface.blit(surface, rect)
            y = rect.bottom + 4
        return y

    def fit_qr_size(self, width: int, height: int) -> tuple[int, int]:
        # QR assets are already high-resolution (512x512) squares, so this only
        # ever scales down — sized generously since it needs to stay scannable.
        target = max(120, min(self.width // 2, int(self.height * 0.45)))
        scale = target / max(1, max(width, height))
        return max(1, int(width * scale)), max(1, int(height * scale))

    def load_support_qr_surface(self, tier_key: str | None, *, large: bool):
        if tier_key is None:
            return None

        cache_key = f"{tier_key}:{'large' if large else 'small'}"
        if cache_key in self.support_qr_surface_cache:
            return self.support_qr_surface_cache[cache_key]

        qr_path = self.support_qr_path_for_tier(tier_key)
        if qr_path is None or not qr_path.exists():
            self.support_qr_surface_cache[cache_key] = None
            return None

        try:
            image = self.pygame.image.load(str(qr_path))
            image = (
                image.convert_alpha()
                if image.get_alpha() is not None
                else image.convert()
            )
            scaled_size = (
                self.fit_qr_size(image.get_width(), image.get_height())
                if large
                else self.fit_preview_size(image.get_width(), image.get_height())
            )
            surface = self.pygame.transform.smoothscale(image, scaled_size)
            self.support_qr_surface_cache[cache_key] = surface
            return surface
        except Exception as exc:
            log_menu_sdl(f"support qr load failed path={qr_path} error={exc}")
            self.support_qr_surface_cache[cache_key] = None
            return None

    def render_support_qr(self, top_y: int) -> int:
        qr_surface = self.load_support_qr_surface(self.support_selected_tier, large=True)
        if qr_surface is None:
            text = self.status_font.render(
                f"QR unavailable — visit {SUPPORT_DONATE_URL}", False, TEXT_COLOR
            )
            rect = text.get_rect(topleft=(LEFT_MARGIN, top_y))
            self.surface.blit(text, rect)
            return rect.bottom

        qr_rect = qr_surface.get_rect(midtop=(self.width // 2, top_y))
        self.surface.blit(qr_surface, qr_rect)
        return qr_rect.bottom

    def support_monthly_preview_tier_key(self) -> str | None:
        if self.view != "support_me_monthly":
            return None

        labels = self.current_labels()
        if not labels or not (0 <= self.selected_index < len(labels)):
            return None

        selected_label = labels[self.selected_index]
        for tier_label, key, _qr in SUPPORT_MONTHLY_TIERS:
            if selected_label == tier_label:
                return key
        return None

    def render_support_monthly_preview(self, top_y: int) -> None:
        tier_key = self.support_monthly_preview_tier_key()
        if tier_key is None:
            return

        qr_surface = self.load_support_qr_surface(tier_key, large=True)
        if qr_surface is None:
            return

        qr_rect = qr_surface.get_rect(topright=(self.width - 24, top_y))
        self.surface.blit(qr_surface, qr_rect)

    def item_start_y(self) -> int:
        title_top = max(36, self.height // 12)
        title_height = self.title_font.get_height()
        status_top = title_top + title_height + 20
        status_height = self.status_font.get_height()
        return status_top + status_height + 34

    def item_gap(self) -> int:
        return max(self.item_font.get_height() + 6, self.height // 18)

    def reset_selection(self) -> None:
        self.selected_index = 0
        self.scroll_offset = 0

    def maybe_offer_smart_cache(self) -> None:
        self.refresh_main_menu_state(force=True)
        self.refresh_cached_games()
        if self.cached_games:
            self.smart_cache_prompt_available = False
            self.smart_cache_prompt_count = 0
            return

        status = should_offer_smart_cache(
            self.storage,
            self.config_data,
            is_online=bool(getattr(self, "main_online", False)),
            has_credentials=bool(getattr(self, "main_logged_in", False)),
        )
        self.smart_cache_prompt_available = status.found_history
        self.smart_cache_prompt_count = status.total_candidates
        if not status.found_history:
            return

        self.save_view_position("main")
        self.view = "smart_cache_prompt"
        self.reset_selection()

    def dismiss_smart_cache_prompt(self) -> None:
        self.smart_cache_prompt_available = False
        self.smart_cache_prompt_count = 0
        self.view = "main"
        self.restore_view_position("main")

    def start_smart_cache(self) -> None:
        if self.smart_cache_in_progress:
            return

        history_paths = load_content_history_paths(self.config_data)
        total_candidates = min(len(history_paths), SMART_CACHE_LIMIT)
        self.smart_cache_in_progress = True
        self.cache_progress_title = "Smart Cache"
        if total_candidates > 0:
            self.cache_progress_text = (
                f"Caching 1/{total_candidates}: {history_paths[0].name}"
            )
        else:
            self.cache_progress_text = "Preparing cache..."
        self.cache_completed = False
        self.cache_abort_requested = False
        self.cache_completion_message = None
        self.cache_return_view = "main"
        self.cache_return_browser_dir = None
        self.cache_return_browser_restore = False
        self.smart_cache_result = None
        self.smart_cache_progress_text = None
        self.view = "cache_progress"
        self.reset_selection()

        def worker() -> None:
            try:
                result = run_smart_cache(
                    self.storage,
                    self.config_data,
                    SMART_CACHE_LIMIT,
                    should_abort=lambda: self.cache_abort_requested,
                    on_progress=self.update_smart_cache_progress,
                )
                self.cache_completion_message = (
                    f"Aborted: scanned {result.scanned}, cached {result.cached}, skipped {result.skipped}"
                    if self.cache_abort_requested
                    else f"Scanned {result.scanned}, cached {result.cached}, skipped {result.skipped}"
                )
                self.cache_completed = True
            except Exception as exc:
                self.cache_completion_message = f"Smart Cache failed: {exc}"
                self.cache_completed = True
            finally:
                self.smart_cache_in_progress = False
                if self.view == "cache_progress" and not self.cache_completed:
                    self.cache_progress_text = None

        self.smart_cache_thread = threading.Thread(target=worker, daemon=True)
        self.smart_cache_thread.start()

    def update_smart_cache_progress(self, progress) -> None:
        self.cache_progress_text = (
            f"Caching {progress.scanned}/{progress.total}: {progress.current_label}"
        )

    def refresh_main_menu_state(self, force: bool = False) -> None:
        if not hasattr(self, "main_state_refreshed_at"):
            self.main_state_refreshed_at = 0.0
        if not hasattr(self, "config_data"):
            self.config_data = {}
        if not hasattr(self, "main_running"):
            self.main_running = False
        if not hasattr(self, "main_online"):
            self.main_online = False
        if not hasattr(self, "main_logged_in"):
            self.main_logged_in = False
        if not hasattr(self, "main_autostart_supported"):
            self.main_autostart_supported = False
        if not hasattr(self, "main_autostart_enabled"):
            self.main_autostart_enabled = False
        if not hasattr(self, "main_update_available"):
            self.main_update_available = False
        if not hasattr(self, "main_update_version"):
            self.main_update_version = None
        if not hasattr(self, "main_update_asset_url"):
            self.main_update_asset_url = None
        if not hasattr(self, "main_update_dialog_seen"):
            self.main_update_dialog_seen = False
        if not hasattr(self, "storage_corruption_active"):
            self.storage_corruption_active = False
        if not hasattr(self, "storage_corruption_notice_seen"):
            self.storage_corruption_notice_seen = False
        if not hasattr(self, "storage_corruption_lost_awards"):
            self.storage_corruption_lost_awards = None
        if not hasattr(self, "storage_corruption_done"):
            self.storage_corruption_done = False

        if not force and self.view != "main":
            return

        now = time.monotonic()
        if (
            not force
            and (now - self.main_state_refreshed_at) < MAIN_MENU_STATE_REFRESH_SECONDS
        ):
            return

        self.config_data = load_config()
        self.main_running = self.read_proxy_running()
        self.main_online = online_check(self.config_data)
        self.main_logged_in = self.is_logged_in(self.config_data)
        self.main_service_mode = service_mode_active()
        if self.main_service_mode:
            self.main_autostart_supported = True
            self.main_autostart_enabled = service_autostart_enabled()
        else:
            self.main_autostart_supported = autostart_supported(self.config_data)
            self.main_autostart_enabled = (
                self.main_autostart_supported
                and is_autostart_enabled(self.config_data)
            )
        if force:
            update_platform = self.update_platform()
            if update_platform is None:
                self.main_update_available = False
                self.main_update_version = None
                self.main_update_asset_url = None
            else:
                try:
                    update = update_status(update_platform)
                    self.main_update_available = update.update_available
                    self.main_update_version = update.latest_version
                    self.main_update_asset_url = update.asset_url
                except Exception as exc:
                    log_menu_sdl(f"update check failed error={exc}")
                    self.main_update_available = False
                    self.main_update_version = None
                    self.main_update_asset_url = None
        self.main_state_refreshed_at = now
        if (
            self.view == "main"
            and self.main_update_available
            and not self.main_update_dialog_seen
        ):
            self.main_update_dialog_seen = True
            self.save_view_position("main")
            self.view = "update_prompt"
            self.reset_selection()

        self.maybe_show_storage_corruption_notice()

    def maybe_show_storage_corruption_notice(self) -> None:
        if self.storage_corruption_notice_seen or self.view != "main":
            return

        incident = storage_corruption.load_incident()
        if incident is None or incident.get("notified"):
            return

        self.storage_corruption_notice_seen = True
        storage_corruption.mark_notified()
        self.storage_corruption_active = True
        self.storage_corruption_lost_awards = incident.get("lost_pending_awards")
        self.storage_corruption_done = False
        self.save_view_position("main")
        self.reset_selection()
        self.log_upload_result = None
        self.view = "send_logs_progress"

        intro = "A corrupted data file was found and reset."

        if incident.get("reported") and incident.get("upload_id"):
            result_text = self.storage_corruption_result_text(True, incident["upload_id"])
            self.log_upload_progress_text = f"{intro}\n{result_text}"
            self.storage_corruption_done = True
            return

        self.log_upload_progress_text = f"{intro}\nUploading diagnostic logs..."

        def worker() -> None:
            try:
                upload_id = report_storage_corruption(incident)
                storage_corruption.mark_reported(upload_id)
                result_text = self.storage_corruption_result_text(True, upload_id)
            except Exception as exc:
                result_text = self.storage_corruption_result_text(False, str(exc))
            self.log_upload_progress_text = f"{intro}\n{result_text}"
            self.storage_corruption_done = True

        self.log_upload_thread = threading.Thread(target=worker, daemon=True)
        self.log_upload_thread.start()

    def storage_corruption_result_text(self, success: bool, message: str) -> str:
        lost = self.storage_corruption_lost_awards
        upload_part = f"Support ID: {message}" if success else f"Log upload failed: {message}"

        if lost == 0:
            return f"No pending achievements were affected.\n{upload_part}"
        if lost is None:
            return f"{upload_part}\nSome progress may not have synced, please reach out on Discord."
        plural = "achievement" if lost == 1 else "achievements"
        return (
            f"{lost} pending {plural} may not have synced.\n{upload_part}\n"
            "Please reach out on Discord."
        )

    def dismiss_update_prompt(self) -> None:
        self.view = "main"
        self.restore_view_position("main")

    def activate_update_prompt_selected(self) -> None:
        if self.selected_index == 0:
            self.install_update()
            return
        self.dismiss_update_prompt()

    def activate_send_logs_confirm(self) -> None:
        self.save_view_position("main")
        self.view = "send_logs_confirm"
        self.reset_selection()

    def activate_send_logs_confirm_selected(self) -> None:
        if self.selected_index == 0:
            self.start_send_logs()
            return
        self.view = "main"
        self.restore_view_position("main")

    def start_send_logs(self) -> None:
        self.storage_corruption_active = False
        self.storage_corruption_lost_awards = None
        self.log_upload_progress_text = "Uploading logs..."
        self.log_upload_result = None
        self.view = "send_logs_progress"
        self.reset_selection()

        def worker() -> None:
            try:
                upload_id = upload_logs()
                self.log_upload_result = (True, upload_id)
            except Exception as exc:
                self.log_upload_result = (False, str(exc))
            finally:
                self.log_upload_progress_text = None
                if self.view == "send_logs_progress":
                    self.view = "send_logs_result"
                    self.reset_selection()

        self.log_upload_thread = threading.Thread(target=worker, daemon=True)
        self.log_upload_thread.start()

    def dismiss_send_logs_result(self) -> None:
        self.log_upload_result = None
        self.storage_corruption_active = False
        self.view = "main"
        self.restore_view_position("main")

    def dismiss_storage_corruption_progress(self) -> None:
        self.storage_corruption_active = False
        self.storage_corruption_done = False
        self.storage_corruption_lost_awards = None
        self.log_upload_progress_text = None
        self.view = "main"
        self.restore_view_position("main")

    def clear_active_game_unlocks(self) -> None:
        self.active_game_unlock_game_id = None
        self.active_game_unlock_count_cached = None
        self.active_game_unlock_titles_cached = []
        self.achievement_preview_surface = None
        self.achievement_preview_game_id = None
        self.achievement_preview_title = None
        self._badge_path_cache = {}
        self._badge_surface_cache = {}

    def refresh_active_game_unlocks(self) -> None:
        if self.active_game is None:
            self.clear_active_game_unlocks()
            return

        self.active_game_unlock_game_id = self.active_game.game_id
        self.active_game_unlock_count_cached = cached_unlock_count(
            self.storage, self.active_game.game_id
        )
        self.active_game_unlock_titles_cached = cached_unlock_titles(
            self.storage, self.active_game.game_id
        )
        self._badge_path_cache = cached_unlock_badge_paths(
            self.storage, self.active_game.game_id
        )
        self._badge_surface_cache = {}

    def save_view_position(self, view: str | None = None) -> None:
        key = view or self.view
        self.view_positions[key] = (self.selected_index, self.scroll_offset)

    def restore_view_position(self, view: str) -> None:
        saved = self.view_positions.get(view)
        if saved is None:
            self.reset_selection()
            return

        self.selected_index, self.scroll_offset = saved

    def save_browser_position(self) -> None:
        if self.browser_dir is None:
            return
        self.browser_positions[str(self.browser_dir)] = (
            self.selected_index,
            self.scroll_offset,
        )

    def restore_browser_position(self, path: Path) -> None:
        saved = self.browser_positions.get(str(path))
        if saved is None:
            self.reset_selection()
            return

        self.selected_index, self.scroll_offset = saved

    def normalize_selection(self, items: list[str], start_y: int, gap: int) -> None:
        if not items:
            self.selected_index = 0
            self.scroll_offset = 0
            return

        self.selected_index = max(0, min(self.selected_index, len(items) - 1))
        max_offset = max(0, len(items) - 1)
        self.scroll_offset = max(0, min(self.scroll_offset, max_offset))
        self.ensure_selection_visible(items, start_y, gap)

    def visible_items(
        self,
        items: list[str],
        positions: list[int],
        start_y: int,
    ) -> tuple[int, list[tuple[int, str]]]:
        end_offset = self.visible_end_offset(positions, self.scroll_offset, start_y)
        visible = [
            (index, items[index]) for index in range(self.scroll_offset, end_offset)
        ]
        return self.scroll_offset, visible

    def item_positions(self, items: list[str], start_y: int, gap: int) -> list[int]:
        positions: list[int] = []
        current_y = start_y
        header_count = (
            self.cached_games_header_count() if self.view == "cached_games" else 0
        )
        first_game_index = header_count
        last_game_index = len(self.cached_games) + header_count - 1
        for index, _label in enumerate(items):
            positions.append(current_y)
            current_y += gap
            if self.view == "cached_games" and header_count > 0 and index == header_count - 1:
                current_y += GROUP_GAP
            if self.view == "cached_games" and index == last_game_index and index >= first_game_index:
                current_y += GROUP_GAP
            if self.view == "cached_games" and len(self.cached_games) == 0 and header_count > 0 and index == header_count - 1:
                current_y -= GROUP_GAP
            if self.view == "game_actions" and index == 0:
                current_y += GROUP_GAP
            if self.view == "game_actions" and index == len(items) - 2:
                current_y += GROUP_GAP
            if self.view == "file_browser" and index == 0 and self.browser_has_cacheable_files():
                current_y += GROUP_GAP
            if self.view == "pending_awards" and index % 2 == 1:
                current_y += GROUP_GAP
        return positions

    def bottom_limit(self) -> int:
        message_padding = 44 if self.message is not None else 4
        return self.height - message_padding

    def visible_end_offset(
        self, positions: list[int], offset: int, start_y: int
    ) -> int:
        if not positions:
            return 0

        bottom_limit = self.bottom_limit()
        item_height = max(1, self.item_font.get_height())
        scroll_base_y = positions[offset] - start_y
        end_offset = offset
        while end_offset < len(positions):
            relative_y = positions[end_offset] - scroll_base_y
            if relative_y + item_height > bottom_limit and end_offset > offset:
                break
            if relative_y + item_height > bottom_limit and end_offset == offset:
                end_offset += 1
                break
            end_offset += 1
        return end_offset

    def ensure_selection_visible(
        self,
        items: list[str],
        start_y: int,
        gap: int,
    ) -> None:
        if self.selected_index < self.scroll_offset:
            self.scroll_offset = self.selected_index
        positions = self.item_positions(items, start_y, gap)
        end_offset = self.visible_end_offset(positions, self.scroll_offset, start_y)
        while self.selected_index >= end_offset and self.scroll_offset < len(items) - 1:
            self.scroll_offset += 1
            end_offset = self.visible_end_offset(positions, self.scroll_offset, start_y)
        self.scroll_offset = max(0, min(self.scroll_offset, max(0, len(items) - 1)))

    def read_proxy_running(self) -> bool:
        try:
            service = service_status() or {}
        except Exception:
            return False
        return bool(service.get("running"))

    def proxy_running(self) -> bool:
        if self.view == "main":
            self.refresh_main_menu_state()
            return self.main_running

        now = time.monotonic()
        checked_at = getattr(self, "proxy_running_checked_at", None)
        if checked_at is None or now - checked_at >= MAIN_MENU_STATE_REFRESH_SECONDS:
            self.main_running = self.read_proxy_running()
            self.proxy_running_checked_at = now
        return self.main_running

    def start_proxy(self) -> None:
        try:
            cfg_skipped = False
            if service_mode_active():
                start_service()
            else:
                cfg_skipped = start_proxy_inline()
            self.refresh_main_menu_state(force=True)
            self.maybe_offer_smart_cache()
            if cfg_skipped:
                log_menu_sdl("start_proxy retroarch cfg missing, patched conf only")
            if self.view != "smart_cache_prompt":
                if cfg_skipped:
                    self.message = (
                        "Proxy started, no RetroArch cfg",
                        time.monotonic() + ERROR_SECONDS,
                    )
                else:
                    self.message = ("Proxy started", time.monotonic() + 1.2)
        except Exception as exc:
            log_action_failure("start_proxy", exc)
            self.message = (f"Start failed: {exc}", time.monotonic() + ERROR_SECONDS)

    def stop_proxy(self) -> None:
        try:
            if service_mode_active():
                stop_service()
                stop_service_process()
            else:
                stop_proxy_inline()
            self.refresh_main_menu_state(force=True)
            self.message = ("Proxy stopped", time.monotonic() + 1.2)
        except Exception as exc:
            log_action_failure("stop_proxy", exc)
            self.message = (f"Stop failed: {exc}", time.monotonic() + ERROR_SECONDS)

    def toggle_autostart(self, config_data: dict) -> None:
        try:
            if service_mode_active():
                if service_autostart_enabled():
                    disable_service_autostart()
                    self.message = ("Autostart disabled", time.monotonic() + 1.2)
                else:
                    enable_service_autostart()
                    self.message = ("Autostart enabled", time.monotonic() + 1.2)
            elif is_autostart_enabled(config_data):
                disable_autostart(config_data)
                self.message = ("Autostart disabled", time.monotonic() + 1.2)
            else:
                enable_autostart(config_data)
                self.message = ("Autostart enabled", time.monotonic() + 1.2)
            self.refresh_main_menu_state(force=True)
        except Exception as exc:
            log_action_failure("toggle_autostart", exc)
            self.message = (
                f"Autostart failed: {exc}",
                time.monotonic() + ERROR_SECONDS,
            )

    def resolve_update_asset_url(self) -> str | None:
        asset_url = getattr(self, "main_update_asset_url", None)
        if asset_url:
            return asset_url
        update_platform = self.update_platform()
        if update_platform is None:
            return None
        update = update_status(update_platform, force=True)
        self.main_update_asset_url = update.asset_url
        self.main_update_version = update.latest_version
        self.main_update_available = update.update_available
        return update.asset_url

    def show_update_progress(self, text: str) -> None:
        # The update install runs synchronously with no event loop, so this
        # paints the message immediately instead of waiting for the next frame.
        self.message = (text, time.monotonic() + 120)
        self.render()
        self.pygame.event.pump()

    def install_update(self) -> None:
        if running_on_muos():
            self.install_update_muos()
            return
        # Each target passes its own layout: Onion and spruce share App/RAOfflineProxy,
        # Allium ships Apps/RAOfflineProxy.pak. Everything else about the flow is common.
        if running_on_allium():
            self.install_update_archive(DEFAULT_ALLIUM_APP_DIR, "Apps")
            return
        if running_on_onion() or running_on_spruce():
            self.install_update_archive(DEFAULT_ONION_APP_DIR, "App")
            return

        self.show_update_progress("Checking for update...")
        asset_url = self.resolve_update_asset_url()
        if not asset_url:
            self.message = ("Update install failed: no installer URL", time.monotonic() + ERROR_SECONDS)
            self.dismiss_update_prompt()
            return

        try:
            self.show_update_progress("Stopping proxy...")
            stop_proxy_inline()
            self.show_update_progress("Downloading update...")
            installer_path = download_knulli_update_installer(asset_url)
            self.show_update_progress("Installing update...")
            self.storage.close()
            close_input_devices(self.input_handles)
            self.pygame.quit()
            os.execv(str(installer_path), [str(installer_path)])
        except Exception as exc:
            self.message = (f"Update install failed: {exc}", time.monotonic() + ERROR_SECONDS)
            self.dismiss_update_prompt()

    def install_update_archive(self, app_dir: Path, archive_root: str) -> None:
        """Zip-archive update flow, shared by every target that ships one.

        `archive_root` is where the app directory sits inside the archive — `App` for
        Onion and spruce, `Apps` for Allium's .pak layout.
        """
        self.show_update_progress("Checking for update...")
        asset_url = self.resolve_update_asset_url()
        if not asset_url:
            self.message = ("Update install failed: no installer URL", time.monotonic() + ERROR_SECONDS)
            self.dismiss_update_prompt()
            return

        try:
            self.show_update_progress("Stopping proxy...")
            stop_proxy_inline()
            self.show_update_progress("Downloading update...")
            archive_path = download_onion_update_archive(asset_url)
            self.show_update_progress("Installing update...")
            install_onion_update_archive(archive_path, app_dir, archive_root)
            self.storage.close()
            close_input_devices(self.input_handles)
            self.pygame.quit()
            launch_script = str(app_dir / "launch.sh")
            os.execv("/bin/sh", ["/bin/sh", launch_script, "menu-sdl"])
        except Exception as exc:
            self.message = (f"Update install failed: {exc}", time.monotonic() + ERROR_SECONDS)
            self.dismiss_update_prompt()

    def install_update_muos(self) -> None:
        self.show_update_progress("Checking for update...")
        asset_url = self.resolve_update_asset_url()
        if not asset_url:
            self.message = ("Update install failed: no installer URL", time.monotonic() + ERROR_SECONDS)
            self.dismiss_update_prompt()
            return

        app_dir = Path("/run/muos/storage/application/RAOfflineProxy")
        try:
            self.show_update_progress("Stopping proxy...")
            stop_proxy_inline()
            # Download outside app_dir so the in-place swap never touches the archive.
            archive_dest = app_dir.parent / ".raofflineproxy-update.muxapp"
            self.show_update_progress("Downloading update...")
            archive_path = download_muos_update_archive(asset_url, archive_dest)
            self.show_update_progress("Installing update...")
            install_muos_update_archive(archive_path, app_dir)
            self.storage.close()
            close_input_devices(self.input_handles)
            self.pygame.quit()
            # Relaunch the updated menu; the muOS frontend stays stopped (we are in-app).
            launch_script = str(app_dir / "launch.sh")
            os.execv("/bin/sh", ["/bin/sh", launch_script, "menu-sdl"])
        except Exception as exc:
            self.message = (f"Update install failed: {exc}", time.monotonic() + ERROR_SECONDS)
            self.dismiss_update_prompt()

    def uninstall(self) -> None:
        if running_on_muos():
            launcher = "/run/muos/storage/application/RAOfflineProxy/uninstall.sh"
        elif running_on_darkos():
            launcher = "/home/ark/raofflineproxy/bin/raofflineproxy-uninstall"
        elif self.is_knulli_platform():
            launcher = "/userdata/system/raofflineproxy/bin/raofflineproxy-uninstall"
        elif running_on_rocknix():
            launcher = "/storage/.local/share/raofflineproxy/bin/raofflineproxy-uninstall"
        else:
            self.message = ("Uninstall is not available on this platform", time.monotonic() + ERROR_SECONDS)
            return

        try:
            self.storage.close()
        except Exception:
            pass
        try:
            close_input_devices(self.input_handles)
        except Exception:
            pass
        os.execv(launcher, [launcher])
