"""Parse the game target shared by the device launcher and desktop runner."""

from __future__ import annotations

import argparse


def game_id(value: str) -> int:
    """Accept a positive RA game ID."""
    try:
        parsed = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("expected a positive game ID") from exc
    if parsed <= 0:
        raise argparse.ArgumentTypeError("expected a positive game ID")
    return parsed


def add_game_argument(parser: argparse.ArgumentParser) -> None:
    """Add the optional direct-game launch target to an argument parser."""
    parser.add_argument("--game-id", type=game_id, help="open this RA game and refresh it only")
