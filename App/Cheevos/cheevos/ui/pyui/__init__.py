"""Bridge to PyUI, SpruceOS's UI toolkit.

This is the only package (besides the desktop runner) allowed to import PyUI modules. PyUI is not
installed as a distribution: Cheevos runs inside PyUI's process (or the desktop runner puts
``main-ui`` on ``sys.path`` first), so nothing here may import PyUI at module import time.
"""
