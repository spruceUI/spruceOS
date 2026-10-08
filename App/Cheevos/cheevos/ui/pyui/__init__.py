"""Bridge to PyUI, SpruceOS's UI toolkit.

This is the only package (besides the desktop shim) allowed to import PyUI modules. PyUI is not
installed as a distribution: its ``main-ui`` directory is put on ``sys.path`` at runtime by
:func:`cheevos.ui.pyui.bootstrap.add_pyui_to_path`, so nothing here may import PyUI at module
import time.
"""
