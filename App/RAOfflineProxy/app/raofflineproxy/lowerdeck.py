"""Chains ROCKNIX's bottom-screen RetroAchievements proxy through ours.

On devices where ROCKNIX detects two connected displays, runemu.sh appends
`cheevos_custom_host = "http://127.0.0.1:4874"` to the --appendconfig file and
starts /usr/share/lowerdeck/ra_proxy.py. That layer outranks retroarch.cfg, so
RetroArch talks to their proxy no matter what we patch, and theirs is a verbatim
pass-through with no cache — offline it answers 502 with an empty body, which
surfaces in RetroArch as "RetroAchievements game load failed: Invalid JSON".

Rather than fight for the port, we start their proxy ourselves with its own
--upstream flag pointed at us:

    RetroArch -> lowerdeck ra_proxy :4874 -> RAOfflineProxy -> retroachievements.org

Their bottom-screen UI still sees every response, and offline its upstream is our
proxy, which is always reachable. runemu.sh only starts ra_proxy when its pgrep
finds none running, so ours stays in charge once it is up.
"""

from __future__ import annotations

import logging
import subprocess
from pathlib import Path

from .config import proxy_base, running_on_rocknix

LOGGER = logging.getLogger("raofflineproxy")

DUAL_SCREEN_FLAG_FILE = Path("/storage/.config/profile.d/080-dual_screen_mode")
RA_PROXY_SCRIPT = Path("/usr/share/lowerdeck/ra_proxy.py")
# Mirrors the pattern runemu.sh greps for, so we can tell whether starting one
# would collide with an instance ROCKNIX already launched.
RA_PROXY_PROCESS_PATTERN = r"python3 .*/lowerdeck/ra_proxy\.py"


def is_dual_screen() -> bool:
    try:
        content = DUAL_SCREEN_FLAG_FILE.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    return "DEVICE_HAS_DUAL_SCREEN=true" in content


def ra_proxy_running() -> bool:
    try:
        result = subprocess.run(
            ["pgrep", "-f", RA_PROXY_PROCESS_PATTERN],
            capture_output=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0


def should_chain_ra_proxy() -> bool:
    return running_on_rocknix() and is_dual_screen() and RA_PROXY_SCRIPT.exists()


def build_ra_proxy_command(config_data: dict) -> list[str]:
    return [
        "python3",
        str(RA_PROXY_SCRIPT),
        "--upstream",
        proxy_base(config_data),
        # Empty needle disables their watchdog. Left on, it calls srv.shutdown()
        # once RetroArch has been gone for its grace period, and the next game
        # launch would have ROCKNIX restart it pointed straight at RA again.
        "--retroarch-process-match",
        "",
    ]


_chained_process: subprocess.Popen | None = None


def ensure_ra_proxy_chained(config_data: dict) -> bool:
    """Starts ROCKNIX's ra_proxy pointed at us. Returns True if we started it."""
    global _chained_process

    if not should_chain_ra_proxy():
        return False

    if ra_proxy_running():
        LOGGER.info(
            "lowerdeck ra_proxy already running; leaving it alone "
            "(it may be pointed straight at RetroAchievements until it exits)"
        )
        return False

    command = build_ra_proxy_command(config_data)
    try:
        _chained_process = subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        LOGGER.warning("Failed to start lowerdeck ra_proxy chained through us: %s", exc)
        return False

    LOGGER.info("Started lowerdeck ra_proxy chained through %s", proxy_base(config_data))
    return True


def stop_ra_proxy_chain() -> bool:
    """Stops the ra_proxy we started. Returns True if we stopped one.

    Its RetroArch watchdog is disabled so it never exits on its own. Leaving it
    behind would point RetroArch at a port we no longer serve, breaking
    achievements outright — worse than the bug this works around. ROCKNIX starts
    its own unchained instance on the next game launch, so stopping ours simply
    restores stock behaviour.
    """
    global _chained_process

    process = _chained_process
    _chained_process = None
    if process is None or process.poll() is not None:
        return False

    try:
        process.terminate()
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
    except (OSError, subprocess.SubprocessError) as exc:
        LOGGER.warning("Failed to stop chained lowerdeck ra_proxy: %s", exc)
        return False

    LOGGER.info("Stopped chained lowerdeck ra_proxy")
    return True
