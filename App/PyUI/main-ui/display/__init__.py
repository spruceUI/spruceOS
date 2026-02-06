"""
Display module with conditional backend loading
- SDL2 backend (pysdl2) for modern devices
- SDL1.2 backend (pygame) for legacy devices like Miyoo Mini
"""

import sys

# Determine which backend to use based on command-line arguments
# This runs at import time, before Device is initialized
_use_pygame = False

# Check if device argument indicates Miyoo Mini (SDL1.2 only)
PYGAME_DEVICES = [
    "MIYOO_MINI",
    "MIYOO_MINI_V4",
    "MIYOO_MINI_PLUS",
    "MIYOO_MINI_FLIP",
    "SPRIG_MIYOO_MINI",
    "SPRIG_MIYOO_MINI_V4",
    "SPRIG_MIYOO_MINI_PLUS",
    "SPRIG_MIYOO_MINI_FLIP"
]

# Parse device from command line args
for i, arg in enumerate(sys.argv):
    if arg == '-device' and i + 1 < len(sys.argv):
        device_type = sys.argv[i + 1]
        if device_type in PYGAME_DEVICES:
            _use_pygame = True
        break

# Conditional import - use relative imports to avoid circular import
if _use_pygame:
    from .display_pygame import Display
    print(f"[PyUI] Using Pygame (SDL1.2) display backend")
else:
    from .display import Display
    print(f"[PyUI] Using PySDL2 (SDL2) display backend")

# Export Display for external imports
__all__ = ['Display']
