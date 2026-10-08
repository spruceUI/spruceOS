"""Colours for progress bars and award indicators, after RetroAchievements' web client.

RA (``PlayerGameProgressBar``, ``AwardIndicator``) draws hardcore progress gold and casual-only
progress grey, side by side. An award gets a small dot: gold for the mastery family, silver for
the beaten family, filled for hardcore and hollow for casual. The percentage takes the award's
colour. On light backgrounds RA switches to a darker gold, and so do we, judging by the row's
background. When a theme's background fights these colours (a yellow theme), everything falls
back to the theme's text colour in three strengths. Hollow vs filled dots still tell casual from
hardcore then.

Pure: no PyUI or SDL, so it is unit-tested on its own.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass

from cheevos.core.models import AwardKind

RGB = tuple[int, int, int]

GOLD = (255, 215, 0)  # RA "gold": mastery
HARDCORE_GOLD = (250, 186, 5)  # midpoint of RA's amber-500 -> gold bar gradient
DARK_GOLD = (202, 138, 4)  # RA yellow-600: completion, and gold on light backgrounds
ZINC_300 = (212, 212, 216)  # RA: beaten
ZINC_400 = (161, 161, 170)  # RA: beaten (casual); the casual bar on dark rows
ZINC_500 = (113, 113, 122)
ZINC_600 = (82, 82, 91)
NEUTRAL_500 = (115, 115, 115)  # RA: the casual bar
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)

LIGHT = 128  # background brightness from which a row counts as light
MIN_CONTRAST = 60  # brightness difference a bar segment needs against its row
TRACK_ALPHA_DARK = 28  # a faint lighter groove on dark rows
TRACK_ALPHA_LIGHT = 40  # a faint darker groove on light rows
FALLBACK_ALPHAS = (255, 140, 60)  # text colour strengths: hardcore, casual, track


def luma(color: RGB) -> float:
    """Return a colour's perceived brightness.

    Args:
        color: RGB colour.

    Returns:
        Brightness, 0-255.
    """
    return 0.299 * color[0] + 0.587 * color[1] + 0.114 * color[2]


@dataclass(frozen=True, slots=True)
class Paint:
    """A fill colour with its opacity.

    Attributes:
        color: RGB colour.
        alpha: Opacity, 0-255.
    """

    color: RGB
    alpha: int = 255


@dataclass(frozen=True, slots=True)
class Marker:
    """An award indicator dot.

    Attributes:
        color: Dot colour (also used for the percentage).
        filled: Hardcore award (filled); casual awards are hollow rings.
    """

    color: RGB
    filled: bool


@dataclass(frozen=True, slots=True)
class Palette:
    """Everything a row's bar needs.

    Attributes:
        hardcore: Hardcore segment.
        casual: Casual-only segment.
        track: The rest of the bar.
        markers: Award indicator per award.
    """

    hardcore: Paint
    casual: Paint
    track: Paint
    markers: Mapping[AwardKind, Marker]


def _fallback(text: RGB) -> Palette:
    """Build the theme-text palette for backgrounds that fight RA's colours.

    Args:
        text: The row's text colour.

    Returns:
        The palette.
    """
    hardcore, casual, track = FALLBACK_ALPHAS
    markers = {
        AwardKind.MASTERED: Marker(text, filled=True),
        AwardKind.COMPLETED: Marker(text, filled=False),
        AwardKind.BEATEN_HARDCORE: Marker(text, filled=True),
        AwardKind.BEATEN_SOFTCORE: Marker(text, filled=False),
    }
    return Palette(Paint(text, hardcore), Paint(text, casual), Paint(text, track), markers)


def palette(background: RGB, text: RGB) -> Palette:
    """Pick RA's colours for a row, or the theme-text fallback when they wouldn't read.

    Args:
        background: The row's (average) background colour.
        text: The row's text colour.

    Returns:
        The palette.
    """
    shade = luma(background)
    light = shade >= LIGHT
    hardcore = DARK_GOLD if light else HARDCORE_GOLD
    casual = NEUTRAL_500 if light else ZINC_400
    if min(abs(luma(hardcore) - shade), abs(luma(casual) - shade)) < MIN_CONTRAST:
        return _fallback(text)
    track = Paint(BLACK, TRACK_ALPHA_LIGHT) if light else Paint(WHITE, TRACK_ALPHA_DARK)
    markers = {
        AwardKind.MASTERED: Marker(DARK_GOLD if light else GOLD, filled=True),
        AwardKind.COMPLETED: Marker(DARK_GOLD, filled=False),
        AwardKind.BEATEN_HARDCORE: Marker(ZINC_600 if light else ZINC_300, filled=True),
        AwardKind.BEATEN_SOFTCORE: Marker(ZINC_500 if light else ZINC_400, filled=False),
    }
    return Palette(Paint(hardcore), Paint(casual), track, markers)
