"""Wake PyUI's idle input wait when a background worker publishes a visible change."""


def request_redraw() -> None:
    """Request a frame from any thread.

    SpruceOS #1890 added this thread-safe notification. It wakes the UI thread without
    drawing on the worker or disturbing an active screensaver (.agents/pyui.md, "Idle frames").
    """
    from controller.controller import Controller

    Controller.request_redraw()
