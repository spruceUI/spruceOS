"""Run an app's launch script while PyUI stays up and shows the script's messages.

An app opts in with "launchInPyUI": true next to its "launch" script in config.json. Instead
of exiting so the CFW can run the script, PyUI runs it through the CFW's runner
("launchInPyUiCmd" in py-ui-config.json; spruce's is spruce/scripts/run_app_in_pyui.sh) and
listens itself on the CFW's realtime message port ("realtimeMessagePort"), the one spruce's
start_pyui_message_writer otherwise starts a second PyUI for. The menu needs no restart and
the script no changes; with PYUI_HOSTS_MESSAGES set,
start_pyui_message_writer leaves the socket to the menu. Without both keys the script runs
after PyUI exits, as before.

For scripts that show progress, maybe ask through an option list, and return. Not for ones
that need PyUI gone: unmounting the card, replacing PyUI's files, restoring settings PyUI keeps
in memory, starting another program that draws to the screen, or leaving a command in
/tmp/cmd_to_run.sh.

For app developers: App/PyUI/docs/apps_in_pyui_readme.txt.
"""

import os
import subprocess

from controller.controller import Controller
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from utils.realtime_message_network_listener import RealtimeMessageNetworkListener

HOSTED_ENV = "PYUI_HOSTS_MESSAGES"


def run(folder, launch):
    """Run the app's script and show its messages. False if PyUI can't host it."""
    logger = PyUiLogger.get_logger()
    runner = PyUiConfig.get_launch_in_pyui_cmd()
    port = PyUiConfig.get_realtime_message_port()
    if not runner or not port or not os.path.isfile(runner):
        return False
    listener = RealtimeMessageNetworkListener(port, hosted=True)
    try:
        listener.bind()
    except OSError:
        # A message writer from elsewhere holds the socket: leave the script to principal.sh.
        logger.warning(f"Message socket {port} is taken; running {launch} after PyUI exits")
        listener.stop()
        return False

    env = _launcher_environment()
    env[HOSTED_ENV] = "1"
    process = subprocess.Popen(
        ["/bin/sh", runner, folder, launch], env=env,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    logger.info(f"Running {launch} inside PyUI (pid {process.pid})")
    try:
        listener.start(until=lambda: process.poll() is not None)
    finally:
        status = process.wait()
        logger.info(f"{launch} exited with status {status}")
        # Presses the script read itself (prompts, option lists) must not reach the menu.
        Controller.clear_input_queue()
    # A trigger left for PyUI's next start (Game Nursery's box art): that start is now.
    from menus.main_menu import MainMenu  # here: the main menu imports the Apps menu
    MainMenu.check_for_boxart_resizing()
    return True


def _launcher_environment():
    """The environment principal.sh gives the commands it runs.

    PyUI's launch.sh sets PyUI's own libraries, preloads and SDL drivers before starting it as
    a child, so its environment as it started is principal.sh's.
    """
    try:
        with open(f"/proc/{os.getppid()}/environ", "rb") as source:
            items = source.read().split(b"\0")
        return dict(os.fsdecode(item).split("=", 1) for item in items if b"=" in item)
    except OSError:
        return dict(os.environ)
