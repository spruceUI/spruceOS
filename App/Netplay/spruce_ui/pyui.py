"""Netplay's entry for spruce's PyUI, which runs apps inside its own process:
config.json's "pyuiEntry": "spruce_ui.pyui:run". PyUI calls run() from the
Apps menu with its display, theme and controller up, and carries on when it
returns. Older PyUI ignores the key and runs "launch" (launch.sh) instead."""


def run() -> None:
    from . import __main__ as app
    app.run_in_pyui()
