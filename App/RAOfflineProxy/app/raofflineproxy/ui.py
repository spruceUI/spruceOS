from __future__ import annotations

import json
import struct
from pathlib import Path

from .config import (
    CONFIG_FILE,
    DATABASE_FILE,
    LOG_FILE,
    detect_retroarch_cfg,
    load_config,
)
from .retroarch_cfg import status_retroarch_cfg
from .state import load_patch_state, load_service_status
from .storage import JSON_STORE_FILE

LOG_TAIL_LINES = 10
IMAGE_LOG_TAIL_LINES = 5
DEFAULT_IMAGE_WIDTH = 640
DEFAULT_IMAGE_HEIGHT = 480
MARGIN_X = 16
MARGIN_Y = 16
GLYPH_WIDTH = 5
GLYPH_HEIGHT = 7
GLYPH_SPACING = 1
LINE_SPACING = 3
DEFAULT_FONT_SCALE = 1
STATUS_FONT_SCALE = 2

FONT = {
    " ": ("00000", "00000", "00000", "00000", "00000", "00000", "00000"),
    "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
    ".": ("00000", "00000", "00000", "00000", "00000", "01100", "01100"),
    "/": ("00001", "00010", "00100", "01000", "10000", "00000", "00000"),
    ":": ("00000", "01100", "01100", "00000", "01100", "01100", "00000"),
    ",": ("00000", "00000", "00000", "00000", "01100", "01100", "01000"),
    "=": ("00000", "11111", "00000", "11111", "00000", "00000", "00000"),
    "<": ("00010", "00100", "01000", "10000", "01000", "00100", "00010"),
    ">": ("01000", "00100", "00010", "00001", "00010", "00100", "01000"),
    "_": ("00000", "00000", "00000", "00000", "00000", "00000", "11111"),
    "(": ("00010", "00100", "01000", "01000", "01000", "00100", "00010"),
    ")": ("01000", "00100", "00010", "00010", "00010", "00100", "01000"),
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "10000", "11110", "00001", "00001", "11110"),
    "6": ("01110", "10000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00001", "01110"),
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01110", "10001", "10000", "10000", "10000", "10001", "01110"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "G": ("01110", "10001", "10000", "10111", "10001", "10001", "01110"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("01110", "00100", "00100", "00100", "00100", "00100", "01110"),
    "J": ("00001", "00001", "00001", "00001", "10001", "10001", "01110"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "Q": ("01110", "10001", "10001", "10001", "10101", "10010", "01101"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "10101", "01010"),
    "X": ("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
    "Y": ("10001", "10001", "01010", "00100", "00100", "00100", "00100"),
    "Z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
    "?": ("01110", "10001", "00001", "00010", "00100", "00000", "00100"),
}


def launch_ui() -> None:
    print(render_plain_text_status())


def write_status_image(
    output_path: str,
    image_width: int = DEFAULT_IMAGE_WIDTH,
    image_height: int = DEFAULT_IMAGE_HEIGHT,
) -> None:
    output = Path(output_path)
    snapshot = collect_snapshot()
    lines = [
        line.upper()
        for line in render_lines(
            snapshot, width=72, height=32, log_limit=0, include_recent_log=False
        )
    ]
    resolved_width, resolved_height = normalize_image_size(image_width, image_height)
    pixels = [[0 for _ in range(resolved_width)] for _ in range(resolved_height)]
    line_height = scaled_line_height(STATUS_FONT_SCALE)

    y = MARGIN_Y
    for line in lines:
        draw_text_line(
            pixels,
            line,
            MARGIN_X,
            y,
            resolved_width,
            resolved_height,
            STATUS_FONT_SCALE,
        )
        y += line_height
        if y + (GLYPH_HEIGHT * STATUS_FONT_SCALE) >= resolved_height - MARGIN_Y:
            break

    if output.suffix.lower() == ".ppm":
        write_ppm(output, pixels, resolved_width, resolved_height)
        return

    write_bmp(output, pixels, resolved_width, resolved_height)


def render_text_pixels(
    text: str,
    width: int = 72,
    height: int = 32,
    image_width: int = DEFAULT_IMAGE_WIDTH,
    image_height: int = DEFAULT_IMAGE_HEIGHT,
    font_scale: int = DEFAULT_FONT_SCALE,
) -> tuple[list[list[int]], int, int]:
    lines = [line.upper() for line in normalize_text_lines(text, width, height)]
    resolved_width, resolved_height = normalize_image_size(image_width, image_height)
    resolved_font_scale = normalize_font_scale(font_scale)
    pixels = [[0 for _ in range(resolved_width)] for _ in range(resolved_height)]
    line_height = scaled_line_height(resolved_font_scale)

    y = MARGIN_Y
    for line in lines:
        draw_text_line(
            pixels,
            line,
            MARGIN_X,
            y,
            resolved_width,
            resolved_height,
            resolved_font_scale,
        )
        y += line_height
        if y + (GLYPH_HEIGHT * resolved_font_scale) >= resolved_height - MARGIN_Y:
            break

    return pixels, resolved_width, resolved_height


def write_text_image(
    output_path: str,
    text: str,
    width: int = 72,
    height: int = 32,
    image_width: int = DEFAULT_IMAGE_WIDTH,
    image_height: int = DEFAULT_IMAGE_HEIGHT,
    font_scale: int = DEFAULT_FONT_SCALE,
) -> None:
    output = Path(output_path)
    pixels, resolved_width, resolved_height = render_text_pixels(
        text,
        width=width,
        height=height,
        image_width=image_width,
        image_height=image_height,
        font_scale=font_scale,
    )

    if output.suffix.lower() == ".ppm":
        write_ppm(output, pixels, resolved_width, resolved_height)
        return

    write_bmp(output, pixels, resolved_width, resolved_height)


def render_plain_text_status() -> str:
    snapshot = collect_snapshot()
    lines = render_lines(snapshot, width=120, height=40, log_limit=LOG_TAIL_LINES)
    return "\n".join(lines)


def collect_snapshot() -> dict:
    config_data = load_config_safe()
    cfg_path = config_data.get("retroarch_cfg") or detect_retroarch_cfg()
    cfg_status = status_retroarch_cfg_safe(cfg_path, config_data)
    service = load_service_status() or {}
    patch_state = load_patch_state() or {}
    storage = load_storage_snapshot()
    recent_log = tail_log(LOG_FILE, LOG_TAIL_LINES)

    return {
        "cfg_status": cfg_status,
        "service": service,
        "patch_state_present": bool(patch_state),
        "storage": storage,
        "recent_log": recent_log,
        "config_file_exists": CONFIG_FILE.exists(),
    }


def render_lines(
    snapshot: dict,
    width: int,
    height: int,
    log_limit: int,
    include_recent_log: bool = True,
) -> list[str]:
    cfg_status = snapshot["cfg_status"]
    service = snapshot["service"]
    storage = snapshot["storage"]
    lines = [
        "RAOfflineProxy UI",
        "",
        f"Service: {'running' if service.get('running') else 'stopped'}",
        f"PID: {service.get('pid', '-')}",
        f"Proxy target: {cfg_status.get('proxy_host', '-')}",
        f"Patch state: {'present' if snapshot['patch_state_present'] else 'missing'}",
        "",
        "RetroArch",
        f"  Config: {cfg_status.get('cfg_path', '-')}",
        f"  Exists: {'yes' if cfg_status.get('exists') else 'no'}",
        f"  Patched: {'yes' if cfg_status.get('is_patched') else 'no'}",
        f"  Cheevos enabled: {'yes' if cfg_status.get('cheevos_enabled') else 'no'}",
        f"  Hardcore enabled: {'yes' if cfg_status.get('hardcore_enabled') else 'no'}",
        "",
        "Storage",
        f"  Backend: {storage.get('backend', '-')}",
        f"  Cached entries: {storage.get('cached_entries', 0)}",
        f"  Pending awards: {storage.get('pending_awards', 0)}",
        f"  Cached games: {storage.get('cached_games', 0)}",
    ]

    if include_recent_log:
        lines.extend(["", "Recent Log"])

        recent_log = snapshot["recent_log"][-log_limit:] if log_limit > 0 else []
        if recent_log:
            lines.extend(f"  {line}" for line in recent_log)
        else:
            lines.append("  <no log entries>")

    return [truncate(line, width) for line in lines]


def truncate(value: str, width: int) -> str:
    if width <= 1:
        return ""
    return value[: max(0, width - 1)]


def normalize_text_lines(text: str, width: int, height: int) -> list[str]:
    raw_lines = text.splitlines() or [""]
    lines = [truncate(line, width) for line in raw_lines[:height]]
    if not lines:
        return [""]
    return lines


def normalize_image_size(width: int, height: int) -> tuple[int, int]:
    resolved_width = width if width > 0 else DEFAULT_IMAGE_WIDTH
    resolved_height = height if height > 0 else DEFAULT_IMAGE_HEIGHT
    return resolved_width, resolved_height


def normalize_font_scale(font_scale: int) -> int:
    return font_scale if font_scale > 0 else DEFAULT_FONT_SCALE


def scaled_line_height(font_scale: int) -> int:
    return (GLYPH_HEIGHT * font_scale) + (LINE_SPACING * font_scale)


def draw_text_line(
    pixels: list[list[int]],
    text: str,
    x: int,
    y: int,
    image_width: int,
    image_height: int,
    font_scale: int,
) -> None:
    cursor_x = x
    glyph_width = GLYPH_WIDTH * font_scale
    glyph_spacing = GLYPH_SPACING * font_scale
    for char in text:
        draw_glyph(
            pixels,
            normalize_glyph(char),
            cursor_x,
            y,
            image_width,
            image_height,
            font_scale,
        )
        cursor_x += glyph_width + glyph_spacing
        if cursor_x + glyph_width >= image_width - MARGIN_X:
            return


def draw_glyph(
    pixels: list[list[int]],
    glyph: tuple[str, ...],
    x: int,
    y: int,
    image_width: int,
    image_height: int,
    font_scale: int,
) -> None:
    for row_index, row in enumerate(glyph):
        pixel_y = y + (row_index * font_scale)
        if pixel_y >= image_height:
            return
        for column_index, value in enumerate(row):
            pixel_x = x + (column_index * font_scale)
            if pixel_x >= image_width:
                return
            if value == "1":
                for y_offset in range(font_scale):
                    for x_offset in range(font_scale):
                        scaled_x = pixel_x + x_offset
                        scaled_y = pixel_y + y_offset
                        if scaled_x < image_width and scaled_y < image_height:
                            pixels[scaled_y][scaled_x] = 255


def normalize_glyph(char: str) -> tuple[str, ...]:
    return FONT.get(char.upper(), FONT["?"])


def write_ppm(
    path: Path, pixels: list[list[int]], image_width: int, image_height: int
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        handle.write(f"P6\n{image_width} {image_height}\n255\n".encode("ascii"))
        for row in pixels:
            rgb_row = bytearray()
            for value in row:
                rgb_row.extend((value, value, value))
            handle.write(rgb_row)


def write_bmp(
    path: Path, pixels: list[list[int]], image_width: int, image_height: int
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    row_size = image_width * 3
    padding_size = (4 - (row_size % 4)) % 4
    pixel_array_size = (row_size + padding_size) * image_height
    file_size = 14 + 40 + pixel_array_size

    with path.open("wb") as handle:
        handle.write(b"BM")
        handle.write(struct.pack("<IHHI", file_size, 0, 0, 54))
        handle.write(
            struct.pack(
                "<IIIHHIIIIII",
                40,
                image_width,
                image_height,
                1,
                24,
                0,
                pixel_array_size,
                2835,
                2835,
                0,
                0,
            )
        )

        padding = b"\x00" * padding_size
        for row in reversed(pixels):
            bmp_row = bytearray()
            for value in row:
                bmp_row.extend((value, value, value))
            handle.write(bmp_row)
            handle.write(padding)


def load_config_safe() -> dict:
    try:
        return load_config()
    except Exception:
        return {}


def status_retroarch_cfg_safe(cfg_path: str, config_data: dict) -> dict:
    try:
        return status_retroarch_cfg(cfg_path, config_data)
    except Exception:
        return {
            "cfg_path": cfg_path,
            "exists": Path(cfg_path).exists(),
            "is_patched": False,
            "cheevos_enabled": False,
            "hardcore_enabled": False,
            "proxy_host": config_data.get("proxy_host", "127.0.0.1:8080"),
        }


def load_storage_snapshot() -> dict:
    if JSON_STORE_FILE.exists():
        try:
            with JSON_STORE_FILE.open(encoding="utf-8") as handle:
                data = json.load(handle)
            cache_entries = data.get("api_cache", [])
            pending_awards = data.get("pending_awards", [])
            return {
                "backend": "json",
                "cached_entries": len(cache_entries),
                "pending_awards": len(pending_awards),
                "cached_games": count_cached_games(cache_entries),
            }
        except Exception:
            return {
                "backend": "json",
                "cached_entries": 0,
                "pending_awards": 0,
                "cached_games": 0,
            }

    if DATABASE_FILE.exists():
        return {
            "backend": "sqlite",
            "cached_entries": -1,
            "pending_awards": -1,
            "cached_games": -1,
        }

    return {
        "backend": "none",
        "cached_entries": 0,
        "pending_awards": 0,
        "cached_games": 0,
    }


def count_cached_games(entries: list[dict]) -> int:
    game_ids: set[str] = set()
    for entry in entries:
        cache_key = str(entry.get("cacheKey", ""))
        if cache_key.startswith("patch:"):
            parts = cache_key.split(":")
            if len(parts) >= 2:
                game_ids.add(parts[1])
    return len(game_ids)


def tail_log(path: Path, limit: int) -> list[str]:
    if not path.exists():
        return []

    try:
        with path.open(encoding="utf-8", errors="replace") as handle:
            lines = handle.readlines()
        return [line.rstrip("\n") for line in lines[-limit:]]
    except Exception:
        return []
