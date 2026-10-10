"""Images the bridge generates at runtime (button glyphs, swatches), and pixel helpers.

They go to a scratch directory (RAM-backed on devices) and are drawn with PyUI's
``Display.render_image`` like any theme asset. That matters for translucency: the Miyoo
Mini's SDL renderer ignores the blend mode for filled rectangles but blends textures, so a
translucent fill must be a stretched translucent image.
"""

from __future__ import annotations

import ctypes
import functools
import struct
import tempfile
import zlib
from pathlib import Path

_SWATCH_SIZE = (256, 16)  # wide, so PyUI's ZOOM crop never rounds a source side to 0 px
_AVERAGE_STRIDE = 7  # sample at least every 7th pixel when averaging an image (prime: no aliasing)
_AVERAGE_SAMPLES = 4096  # enough for an average; a 640x480 background took 0.4 s on a Mini

RGB = tuple[int, int, int]

_state: dict[str, Path] = {}


def use_scratch(path: Path) -> None:
    """Write generated images into ``path`` from now on.

    Args:
        path: Directory (created when needed; the app deletes it on exit).
    """
    _state["scratch"] = path


def scratch() -> Path:
    """Return the directory for generated images.

    Returns:
        The configured directory, or one under the system temp directory.
    """
    return _state.get("scratch") or Path(tempfile.gettempdir()) / "cheevos-ui"


def encode_png(width: int, height: int, rgba: bytes) -> bytes:
    """Encode RGBA pixels as a PNG (stdlib only; SDL_image can't always save PNG on devices).

    Args:
        width: Image width.
        height: Image height.
        rgba: 4 bytes per pixel, rows top to bottom.

    Returns:
        The PNG file contents.
    """

    def chunk(kind: bytes, data: bytes) -> bytes:
        """Frame one PNG chunk."""
        crc = zlib.crc32(kind + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", crc)

    stride = width * 4
    raw = b"".join(b"\x00" + rgba[row * stride : (row + 1) * stride] for row in range(height))
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


def write(name: str, width: int, height: int, rgba: bytes) -> Path:
    """Write a generated image once (an existing file is reused).

    Args:
        name: File name, unique for the content.
        width: Image width.
        height: Image height.
        rgba: Pixels.

    Returns:
        The file.
    """
    path = scratch() / name
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(encode_png(width, height, rgba))
    return path


def swatch(color: tuple[int, int, int], alpha: int, *, tall: bool = False) -> Path:
    """Return a plain translucent colour image, to be stretched over a rectangle.

    PyUI's ZOOM scaling crops the source to the target's shape, so a thin target needs a
    swatch of the same orientation: wide for horizontal strips, ``tall`` for vertical ones.

    Args:
        color: RGB colour.
        alpha: Opacity, 0-255.
        tall: For rectangles taller than wide.

    Returns:
        The image.
    """
    width, height = _SWATCH_SIZE[::-1] if tall else _SWATCH_SIZE
    shape = "t" if tall else "w"
    name = "swatch-{:02x}{:02x}{:02x}{:02x}-{}.png".format(*color, alpha, shape)
    return write(name, width, height, bytes((*color, alpha)) * (width * height))


def luma(color: RGB) -> float:
    """Return a colour's perceived brightness.

    Args:
        color: RGB colour.

    Returns:
        Brightness, 0-255.
    """
    return 0.299 * color[0] + 0.587 * color[1] + 0.114 * color[2]


def inside_rounded(px: float, py: float, width: float, height: float, radius: float) -> bool:
    """Whether a point lies inside a rounded rectangle at the origin.

    Args:
        px: Point x.
        py: Point y.
        width: Rectangle width.
        height: Rectangle height.
        radius: Corner radius (half the size: a circle).

    Returns:
        ``True`` if inside.
    """
    cx = min(max(px, radius), width - radius)
    cy = min(max(py, radius), height - radius)
    return (px - cx) ** 2 + (py - cy) ** 2 <= radius**2


def surface_rgba(surface: object) -> tuple[int, int, bytes]:
    """Copy an SDL surface's pixels as RGBA bytes.

    Args:
        surface: ``SDL_Surface`` pointer.

    Returns:
        ``(width, height, pixels)`` with 4 bytes per pixel and no row padding.
    """
    import sdl2

    converted = sdl2.SDL_ConvertSurfaceFormat(surface, sdl2.SDL_PIXELFORMAT_RGBA32, 0)
    try:
        width, height, pitch = converted.contents.w, converted.contents.h, converted.contents.pitch
        data = ctypes.string_at(converted.contents.pixels, pitch * height)
        rows = (data[row * pitch : row * pitch + width * 4] for row in range(height))
        return width, height, b"".join(rows)
    finally:
        sdl2.SDL_FreeSurface(converted)


def load_rgba(path: str) -> tuple[int, int, bytes] | None:
    """Load an image as RGBA bytes.

    Args:
        path: Image file.

    Returns:
        ``(width, height, pixels)`` with 4 bytes per pixel and no row padding, or ``None``.
    """
    import sdl2
    from sdl2 import sdlimage

    loaded = sdlimage.IMG_Load(path.encode())
    if not loaded:
        return None
    try:
        return surface_rgba(loaded)
    finally:
        sdl2.SDL_FreeSurface(loaded)


def average_pixels(pixels: bytes, under: RGB = (0, 0, 0)) -> RGB:
    """Average RGBA pixels, each composited over ``under``.

    Args:
        pixels: RGBA bytes.
        under: Colour showing through transparent pixels.

    Returns:
        The average colour.
    """
    totals = [0.0, 0.0, 0.0]
    count = 0
    for offset in range(0, len(pixels) - 3, 4 * _stride(len(pixels) // 4)):
        alpha = pixels[offset + 3] / 255
        for channel in range(3):
            totals[channel] += pixels[offset + channel] * alpha + under[channel] * (1 - alpha)
        count += 1
    if not count:
        return under
    red, green, blue = (round(total / count) for total in totals)
    return red, green, blue


def _stride(pixels: int) -> int:
    """Return the prime step that samples at most ``_AVERAGE_SAMPLES`` of an image's pixels.

    A prime step doesn't line up with stripes or rows of a regular pattern.

    Args:
        pixels: Number of pixels.

    Returns:
        The step, at least ``_AVERAGE_STRIDE``.
    """
    step = max(_AVERAGE_STRIDE, -(-pixels // _AVERAGE_SAMPLES))
    while any(step % divisor == 0 for divisor in range(2, int(step**0.5) + 1)):
        step += 1
    return step


@functools.lru_cache(maxsize=16)
def average_color(path: str, under: RGB = (0, 0, 0)) -> RGB:
    """Average colour of an image composited over ``under`` (theme backgrounds, highlights).

    Args:
        path: Image file.
        under: Colour showing through transparent pixels.

    Returns:
        The average colour (``under`` when the image can't be read).
    """
    loaded = load_rgba(path)
    return average_pixels(loaded[2], under) if loaded else under
