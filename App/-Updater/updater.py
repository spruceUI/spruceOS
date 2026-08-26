#!/usr/bin/env python3

"""
spruceOS EZ Updater.

Supports:
    - Full OTA updates
    - Incremental OTA update chains
    - Stable -> nightly incremental updates

The downloader creates:
    /mnt/SDCARD/App/-OTA/tmp/ota_queue

Each queue line has:
    VERSION|CHECKSUM|LINK|SIZE|INFO|TYPE|FROM

FROM is the version the archive must be applied on top of (older queues
without it are still accepted, but their chain cannot be validated).

TYPE is:
    FULL
    DIFF
    DIFF_NIGHTLY

All required archives are downloaded before this script is launched.

Expects to be launched from launch.sh which sources helperFunctions.sh,
so platform environment variables (PLATFORM, SD_DEV, BATTERY, LED_PATH, etc.)
are available.
"""

import glob
import hashlib
import json
import logging
import os
import re
import socket
import subprocess
import sys
import time
from pathlib import Path


SD_ROOT = "/mnt/SDCARD"
APP_DIR = f"{SD_ROOT}/App/-Updater"
OTA_TMP_DIR = f"{SD_ROOT}/App/-OTA/tmp"
LOG_LOCATION = f"{SD_ROOT}/Saves/spruce/updater.log"
FLAGS_DIR = f"{SD_ROOT}/spruce/flags"
LOGO = f"{APP_DIR}/updater.png"
BAD_IMG = f"{SD_ROOT}/spruce/imgs/notfound.png"
CONFIG_FILE = f"{SD_ROOT}/Saves/spruce/spruce-config.json"
VERSION_FILE = f"{SD_ROOT}/spruce/spruce"
APP_CONFIG = f"{APP_DIR}/config.json"
QUEUE_FILE = f"{OTA_TMP_DIR}/ota_queue"

PERFORM_DELETION = True
DELETE_UPDATE = True


# Read platform vars from environment (set by helperFunctions.sh)
PLATFORM = os.environ.get("PLATFORM", "MiyooMini")

SD_DEV = os.environ.get(
    "SD_DEV",
    "/dev/mmcblk0p1"
)

SD_MOUNTPOINT = os.environ.get(
    "SD_MOUNTPOINT",
    SD_ROOT
)

LED_PATH = os.environ.get(
    "LED_PATH",
    "not applicable"
)

BATTERY_PATH = os.environ.get(
    "BATTERY",
    "/sys/class/power_supply/battery"
)


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

def setup_logging():
    os.makedirs(
        os.path.dirname(LOG_LOCATION),
        exist_ok=True
    )

    logger = logging.getLogger("updater")
    logger.setLevel(logging.DEBUG)

    handler = logging.FileHandler(
        LOG_LOCATION,
        mode="w",
        encoding="utf-8"
    )

    handler.setFormatter(
        logging.Formatter(
            "%(asctime)s - %(message)s",
            "%Y-%m-%d %H:%M:%S"
        )
    )

    logger.addHandler(handler)

    return logger


log = setup_logging()


# ---------------------------------------------------------------------------
# PyUI
# ---------------------------------------------------------------------------

class PyUiMessenger:

    SOCKET_ADDR = b"\x0050980"

    def send(self, msg):
        try:
            s = socket.socket(
                socket.AF_UNIX,
                socket.SOCK_STREAM
            )

            s.settimeout(0.5)
            s.connect(self.SOCKET_ADDR)

            s.sendall(
                (msg + "\n").encode("utf-8")
            )

            s.close()

        except Exception:
            pass

    def image_and_text(
        self,
        image,
        size,
        img_y,
        text,
        text_y=75
    ):
        self.send(
            json.dumps({
                "cmd": "IMAGE_AND_TEXT",
                "args": [
                    image,
                    text,
                    str(size),
                    str(img_y),
                    str(text_y)
                ]
            })
        )

    def progress_bar(
        self,
        text,
        percent,
        bottom=""
    ):
        args = [
            text,
            str(percent)
        ]

        if bottom:
            args.append(bottom)

        self.send(
            json.dumps({
                "cmd": "TEXT_WITH_PERCENTAGE_BAR",
                "args": args
            })
        )


ui = PyUiMessenger()


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def run(cmd, **kw):
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)

    if isinstance(cmd, str):
        kw["shell"] = True

    return subprocess.run(cmd, **kw)


def killall(*names, signal="-9"):
    for name in names:
        run([
            "killall",
            signal,
            name
        ])


def flag_check(name):
    return any(
        os.path.exists(path)
        for path in (
            f"{FLAGS_DIR}/{name}",
            f"{FLAGS_DIR}/{name}.lock",
            f"/tmp/{name}.lock"
        )
    )


def flag_add(name, tmp=False):
    dest = "/tmp" if tmp else FLAGS_DIR

    os.makedirs(
        dest,
        exist_ok=True
    )

    Path(
        f"{dest}/{name}.lock"
    ).touch()


def flag_remove(name):
    for path in (
        f"{FLAGS_DIR}/{name}.lock",
        f"/tmp/{name}.lock"
    ):
        try:
            os.remove(path)
        except OSError:
            pass


def get_config_value(
    key_path,
    default=""
):
    try:
        result = run([
            "jq",
            "-r",
            f'{key_path} // "{default}"',
            CONFIG_FILE
        ])

        if result.returncode == 0:
            return result.stdout.strip()

    except Exception:
        pass

    return default


def read_sysfs(
    path,
    default=""
):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return default


def set_led_trigger(trigger):
    if LED_PATH != "not applicable":
        try:
            Path(
                f"{LED_PATH}/trigger"
            ).write_text(trigger)
        except OSError:
            pass


def version_base(version):
    """
    "v4.4.1-20260826" -> "4.4.1"

    Nightly versions carry a "-<date>" suffix, but the installed
    spruce/spruce file only ever holds the base version.
    """
    if not version:
        return ""

    version = version.strip()

    if version.startswith("v"):
        version = version[1:]

    return version.split("-", 1)[0]


def parse_version(version):
    try:
        return tuple(
            int(x)
            for x in version_base(version).split(".")
        )
    except (ValueError, AttributeError):
        return (0,)


# ---------------------------------------------------------------------------
# PyUI lifecycle
# ---------------------------------------------------------------------------

def start_pyui():

    run([
        "ifconfig",
        "lo",
        "up"
    ])

    run([
        "ifconfig",
        "lo",
        "127.0.0.1"
    ])

    if run(
        ["pgrep", "-f", "sgDisplayRealtimePort"]
    ).returncode == 0:
        return

    listener = (
        f"{SD_ROOT}/App/PyUI/"
        "realtime_message_network_listener.txt"
    )

    try:
        os.remove(listener)
    except OSError:
        pass

    subprocess.Popen(
        [
            f"{SD_ROOT}/App/PyUI/launch.sh",
            "-msgDisplayRealtimePort",
            "50980"
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    while not os.path.exists(listener):
        time.sleep(0.1)


def stop_pyui():

    result = run(
        ["pgrep", "-f", "sgDisplayRealtimePort"]
    )

    if result.returncode == 0:

        ui.send(
            json.dumps({
                "cmd": "EXIT_APP",
                "args": []
            })
        )

        time.sleep(0.5)

        for pid in result.stdout.strip().split():
            run([
                "kill",
                pid
            ])

        time.sleep(1)


# ---------------------------------------------------------------------------
# SD card checks
# ---------------------------------------------------------------------------

def read_only_check():

    log.info(
        "Performing read-only check"
    )

    os.makedirs(
        FLAGS_DIR,
        exist_ok=True
    )

    test_file = (
        f"{FLAGS_DIR}/test-{int(time.time())}"
    )

    try:
        Path(test_file).write_text(
            "testing!"
        )

        if Path(test_file).read_text() != "testing!":
            log.warning(
                "SD card likely read-only "
                "(data mismatch)"
            )
            return

        os.remove(test_file)

    except OSError:
        log.warning(
            "SD card likely read-only "
            "(write failed)"
        )
        return

    for line in run(["mount"]).stdout.splitlines():

        if SD_DEV in line and "(ro" in line:

            log.warning(
                "SD card mounted RO, "
                "attempting remount"
            )

            run([
                "mount",
                "-o",
                "remount,rw",
                SD_DEV,
                SD_MOUNTPOINT
            ])

            break


def check_sd_health():

    test_file = (
        f"{SD_ROOT}/.sd_test_{os.getpid()}"
    )

    try:
        Path(test_file).write_text("test")

        ok = (
            Path(test_file).read_text() == "test"
        )

        os.remove(test_file)

        if not ok:

            ui.image_and_text(
                BAD_IMG,
                35,
                25,
                "SD card error: Read failed"
            )

            time.sleep(5)

            return False

    except OSError:

        ui.image_and_text(
            BAD_IMG,
            35,
            25,
            "SD card error: Write failed"
        )

        time.sleep(5)

        return False

    try:

        stat = os.statvfs(SD_ROOT)

        free_kb = (
            stat.f_bavail * stat.f_frsize
        ) // 1024

        if free_kb < 1024:

            ui.image_and_text(
                BAD_IMG,
                35,
                25,
                "SD card error: No free space"
            )

            time.sleep(5)

            return False

    except OSError:

        ui.image_and_text(
            BAD_IMG,
            35,
            25,
            "SD card error: Cannot check space"
        )

        time.sleep(5)

        return False

    log.info(
        "SD card is healthy."
    )

    return True


# ---------------------------------------------------------------------------
# Queue handling
# ---------------------------------------------------------------------------

def load_queue():

    if not os.path.isfile(QUEUE_FILE):
        return []

    updates = []

    try:

        with open(
            QUEUE_FILE,
            "r",
            encoding="utf-8"
        ) as queue:

            for line_number, line in enumerate(
                queue,
                start=1
            ):

                line = line.strip()

                if not line:
                    continue

                parts = line.split("|")

                # VERSION|CHECKSUM|LINK|SIZE|INFO|TYPE[|FROM]
                # FROM is the version this archive must be applied on.
                if len(parts) not in (6, 7):

                    raise ValueError(
                        f"Invalid queue entry on line "
                        f"{line_number}: {line}"
                    )

                (
                    version,
                    checksum,
                    link,
                    size,
                    info,
                    update_type
                ) = parts[:6]

                from_version = parts[6] if len(parts) == 7 else ""

                if not re.fullmatch(
                    r"[0-9a-fA-F]{32}",
                    checksum
                ):

                    raise ValueError(
                        f"Invalid checksum on line "
                        f"{line_number}"
                    )

                if update_type not in (
                    "FULL",
                    "DIFF",
                    "DIFF_NIGHTLY"
                ):

                    raise ValueError(
                        f"Unknown update type "
                        f"'{update_type}' on line "
                        f"{line_number}"
                    )

                filename = os.path.basename(link)

                if not filename:

                    raise ValueError(
                        f"Invalid archive link on line "
                        f"{line_number}"
                    )

                updates.append({
                    "version": version,
                    "checksum": checksum,
                    "link": link,
                    "size": size,
                    "info": info,
                    "type": update_type,
                    "from": from_version,
                    "filename": filename,
                    "path": f"{SD_ROOT}/{filename}"
                })

    except (
        OSError,
        ValueError
    ) as exc:

        log.error(
            f"Failed reading OTA queue: {exc}"
        )

        return None

    return updates


# ---------------------------------------------------------------------------
# Checksum / chain validation
# ---------------------------------------------------------------------------

def file_md5(path):

    digest = hashlib.md5()

    with open(path, "rb") as f:

        for chunk in iter(
            lambda: f.read(1024 * 1024),
            b""
        ):
            digest.update(chunk)

    return digest.hexdigest()


def verify_checksum(archive, expected):
    """
    Re-verify the archive before anything destructive happens. The
    downloader verified it once, but the file may have sat on the card
    for days ("install later") or been replaced since.
    """

    try:
        actual = file_md5(archive)

    except OSError as exc:

        log.error(
            f"Could not read {archive}: {exc}"
        )

        return False

    if actual.lower() != expected.lower():

        log.error(
            f"Checksum mismatch for {archive}: "
            f"expected {expected}, got {actual}"
        )

        return False

    return True


def validate_incremental_chain(updates, installed_version):
    """
    Return an error message if the queued chain cannot be applied
    on top of the installed version, else None.

    Accepts an installed version that is one of the chain's targets:
    that is a re-run after an interrupted attempt, and re-applying
    the whole chain from the start is safe (every diff is a full-file
    replacement plus explicit deletions).
    """

    expected = None

    for index, update in enumerate(
        updates,
        start=1
    ):

        base = update["from"]

        if not base:

            log.warning(
                f"Queue entry {index} has no FROM version; "
                "chain continuity cannot be verified"
            )

            expected = update["version"]

            continue

        if (
            expected is not None
            and version_base(base) != version_base(expected)
        ):

            return (
                f"Update chain is not continuous: "
                f"entry {index} expects {base} but the "
                f"previous entry installs {expected}."
            )

        expected = update["version"]

    base = updates[0]["from"]

    if not base or not installed_version:
        return None

    installed_base = version_base(installed_version)

    if installed_base == version_base(base):
        return None

    targets = {
        version_base(update["version"])
        for update in updates
    }

    if installed_base in targets:

        log.warning(
            f"Installed version {installed_version} is "
            "inside the queued chain (previous attempt "
            "was interrupted); re-applying the whole chain."
        )

        return None

    return (
        f"Installed version {installed_version} does not "
        f"match the update base {base}. "
        "Run 'Check for Updates' again."
    )


# ---------------------------------------------------------------------------
# Archive verification
# ---------------------------------------------------------------------------

def verify_full_archive(archive):

    result = run([
        "7zr",
        "l",
        archive
    ])

    if result.returncode != 0:

        log.error(
            f"Could not read full archive: {archive}"
        )

        return False

    listing = result.stdout

    required = [
        ".tmp_update",
        "App",
        "spruce"
    ]

    missing = []

    for directory in required:

        if not re.search(
            rf"^.*D.*\s{re.escape(directory)}$",
            listing,
            re.MULTILINE
        ):
            missing.append(directory)

    if missing:

        log.error(
            "Missing directories in full archive: "
            + " ".join(missing)
        )

        return False

    return True


def verify_incremental_archive(archive):

    result = run([
        "7zr",
        "l",
        "-scsUTF-8",
        archive
    ])

    if result.returncode != 0:

        log.error(
            f"Could not read incremental archive: "
            f"{archive}"
        )

        return False

    listing = result.stdout

    has_manifest = False
    has_delete = False

    for line in listing.splitlines():

        if re.search(
            r"\.ota_manifest$",
            line
        ):
            has_manifest = True

        if re.search(
            r"\.ota_delete$",
            line
        ):
            has_delete = True

    if not has_manifest:

        log.error(
            f"Incremental archive missing "
            f".ota_manifest: {archive}"
        )

        return False

    if not has_delete:

        log.error(
            f"Incremental archive missing "
            f".ota_delete: {archive}"
        )

        return False

    return True


# ---------------------------------------------------------------------------
# Incremental deletion
# ---------------------------------------------------------------------------

def prune_empty_parents(path):
    """
    Git never tracks directories, so a deletion list only names files.
    Remove directories left empty by those deletions, stopping at the
    first non-empty parent. This also lets a later archive replace a
    directory with a file of the same name.
    """

    root = os.path.normpath(SD_ROOT)

    parent = os.path.dirname(
        os.path.normpath(path)
    )

    while parent.startswith(root + os.sep):

        try:
            os.rmdir(parent)

        except OSError:
            break

        log.info(
            f"Removed empty directory: {parent}"
        )

        parent = os.path.dirname(parent)


def safe_delete_relative(relative_path):
    """
    Delete one path relative to SD_ROOT.

    This intentionally refuses:
        ""
        "."
        ".."
        "/"
        absolute paths
        paths which escape SD_ROOT
    """

    relative_path = relative_path.strip()

    if not relative_path:
        return True

    if relative_path in (
        ".",
        "..",
        "/"
    ):

        log.warning(
            f"Skipping unsafe deletion entry: "
            f"{relative_path}"
        )

        return False

    if os.path.isabs(relative_path):

        log.warning(
            f"Skipping absolute deletion entry: "
            f"{relative_path}"
        )

        return False

    target = os.path.normpath(
        os.path.join(
            SD_ROOT,
            relative_path
        )
    )

    root = os.path.normpath(
        SD_ROOT
    )

    if target == root:

        log.warning(
            "Skipping deletion of SD root"
        )

        return False

    if not target.startswith(
        root + os.sep
    ):

        log.warning(
            f"Skipping path outside SD root: "
            f"{relative_path}"
        )

        return False

    if os.path.lexists(target):

        log.info(
            f"Incremental OTA deleting: {target}"
        )

        try:

            if (
                os.path.isdir(target)
                and not os.path.islink(target)
            ):

                subprocess.run(
                    [
                        "rm",
                        "-rf",
                        "--",
                        target
                    ],
                    check=True
                )

            else:
                os.remove(target)

        except OSError as exc:

            log.error(
                f"Failed deleting {target}: {exc}"
            )

            return False

        prune_empty_parents(target)

    return True


def extract_delete_list_from_archive(archive):
    """
    Extract only .ota_delete into a temporary directory,
    without extracting the rest of the incremental archive.
    """

    temp_dir = (
        f"{OTA_TMP_DIR}/delete_manifest"
    )

    subprocess.run([
        "rm",
        "-rf",
        temp_dir
    ])

    os.makedirs(
        temp_dir,
        exist_ok=True
    )

    result = run([
        "7zr",
        "x",
        "-y",
        "-scsUTF-8",
        archive,
        ".ota_delete",
        f"-o{temp_dir}"
    ])

    if result.returncode != 0:

        log.error(
            f"Failed extracting .ota_delete "
            f"from {archive}"
        )

        return None

    delete_file = (
        f"{temp_dir}/.ota_delete"
    )

    if not os.path.isfile(delete_file):

        log.error(
            f".ota_delete not found after "
            f"extraction: {archive}"
        )

        return None

    return delete_file


def apply_incremental_deletions(archive):

    delete_file = (
        extract_delete_list_from_archive(
            archive
        )
    )

    if not delete_file:
        return False

    success = True

    try:

        with open(
            delete_file,
            "r",
            encoding="utf-8"
        ) as f:

            for line in f:

                path = line.rstrip(
                    "\r\n"
                )

                if not path:
                    continue

                if not safe_delete_relative(path):
                    success = False

    except OSError as exc:

        log.error(
            f"Could not read incremental "
            f"deletion list: {exc}"
        )

        return False

    return success


# ---------------------------------------------------------------------------
# Extraction
# ---------------------------------------------------------------------------

def extract_with_progress(
    archive,
    label,
    total_hint=None,
    exclude=()
):
    """
    Extract an archive into SD_ROOT.

    This is used for both full and incremental archives.
    `exclude` names archive entries that must not be written to the
    card (the incremental metadata files).
    """

    result = run([
        "7zr",
        "l",
        "-scsUTF-8",
        archive
    ])

    if result.returncode == 0:

        total = sum(
            1
            for line in result.stdout.splitlines()
            if re.match(
                r"^\s*\d{4}-",
                line
            )
        )

    else:
        total = 1

    if total_hint:
        total = max(
            total,
            total_hint
        )

    total = max(
        total,
        1
    )

    log.info(
        f"Extracting {label}: {total} files"
    )

    count = 0
    last_pct = -1

    with open(
        LOG_LOCATION,
        "a"
    ) as errlog:

        proc = subprocess.Popen(
            [
                "7zr",
                "x",
                "-y",
                "-scsUTF-8",
                "-bb1"
            ]
            + [
                f"-x!{name}"
                for name in exclude
            ]
            + [archive],
            stdout=subprocess.PIPE,
            stderr=errlog,
            text=True,
            bufsize=1,
            cwd=SD_ROOT
        )

        for line in proc.stdout:

            name = (
                line.strip()
                .lstrip("- ")
            )

            if not name:
                continue

            if name.startswith(
                (
                    "ERROR",
                    "WARNING",
                    "Cannot",
                    "Can not",
                    "Skipping"
                )
            ):

                log.warning(
                    f"7zr: {name}"
                )

                continue

            count += 1

            pct = (
                count * 100 // total
            )

            if (
                pct != last_pct
                or count == total
            ):

                ui.progress_bar(
                    name,
                    pct,
                    f"{count} / {total} files"
                )

                last_pct = pct

        proc.wait()

    return proc.returncode


# ---------------------------------------------------------------------------
# Full update cleanup
# ---------------------------------------------------------------------------

def run_full_cleanup():

    if not PERFORM_DELETION:

        log.info(
            "Skipping full-update deletion process"
        )

        ui.image_and_text(
            LOGO,
            35,
            25,
            "Skipping file deletion..."
        )

        time.sleep(3)

        return True

    deletion_script = (
        f"{APP_DIR}/delete_files.sh"
    )

    ui.image_and_text(
        LOGO,
        35,
        25,
        "Cleaning up your SD card..."
    )

    try:

        os.chmod(
            deletion_script,
            0o777
        )

        result = run([
            deletion_script
        ])

        if result.stdout:

            log.info(
                "delete_files.sh output:\n"
                + result.stdout
            )

        if result.returncode != 0:

            log.error(
                "delete_files.sh failed with "
                f"code {result.returncode}"
            )

            ui.image_and_text(
                LOGO,
                35,
                25,
                "Cleanup failed!"
            )

            time.sleep(5)

            return False

        ui.image_and_text(
            LOGO,
            35,
            25,
            "SD card cleaned up..."
        )

        time.sleep(2)

        return True

    except OSError as exc:

        log.error(
            f"Could not execute delete_files.sh: {exc}"
        )

        ui.image_and_text(
            LOGO,
            35,
            25,
            "Cleanup failed!"
        )

        time.sleep(5)

        return False


# ---------------------------------------------------------------------------
# Backup / restore
# ---------------------------------------------------------------------------

def run_backup():

    backup_script = (
        f"{SD_ROOT}/App/spruceBackup/"
        "spruceBackup.sh"
    )

    log.info(
        "Running spruceBackup"
    )

    try:

        result = subprocess.run(
            [backup_script],
            timeout=300
        )

        if result.returncode != 0:

            log.error(
                f"spruceBackup failed with "
                f"code {result.returncode}"
            )

            return False

    except (
        OSError,
        subprocess.TimeoutExpired
    ) as exc:

        log.error(
            f"spruceBackup failed: {exc}"
        )

        return False

    return True


def run_restore():

    restore_script = (
        f"{SD_ROOT}/App/spruceRestore/"
        "spruceRestore.sh"
    )

    log.info(
        "Running spruceRestore"
    )

    try:

        result = subprocess.run(
            [restore_script],
            timeout=300
        )

        if result.returncode != 0:

            log.error(
                f"spruceRestore failed with "
                f"code {result.returncode}"
            )

            return False

    except (
        OSError,
        subprocess.TimeoutExpired
    ) as exc:

        log.error(
            f"spruceRestore failed: {exc}"
        )

        return False

    return True


# ---------------------------------------------------------------------------
# Version / flags
# ---------------------------------------------------------------------------

def restore_flags(
    developer_mode,
    tester_mode,
    beta
):

    if developer_mode:

        os.makedirs(
            FLAGS_DIR,
            exist_ok=True
        )

        flag_add(
            "developer_mode"
        )

    if tester_mode:

        flag_remove(
            "developer_mode"
        )

        flag_add(
            "tester_mode"
        )

    if beta:

        Path(
            f"{FLAGS_DIR}/beta"
        ).touch()


def get_update_channel():

    if flag_check(
        "developer_mode"
    ):
        return "nightly"

    if flag_check(
        "tester_mode"
    ):
        return "nightly"

    return "stable"


# ---------------------------------------------------------------------------
# Archive cleanup
# ---------------------------------------------------------------------------

def delete_update_files(updates):

    if not DELETE_UPDATE:

        log.info(
            "DELETE_UPDATE=False; "
            "keeping OTA archives"
        )

        return

    log.info(
        "Deleting successfully applied "
        "OTA archives"
    )

    for update in updates:

        path = update["path"]

        try:

            if os.path.isfile(path):

                os.remove(path)

                log.info(
                    f"Deleted {path}"
                )

        except OSError as exc:

            log.warning(
                f"Could not delete {path}: {exc}"
            )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def fail(
    msg,
    code=1
):

    log.error(msg)

    ui.image_and_text(
        BAD_IMG,
        35,
        25,
        msg
    )

    time.sleep(5)

    sys.exit(code)


def main():

    killall(
        "idlemon",
        "idlemon_mm.sh",
        signal="-TERM"
    )

    subprocess.run([
        "sync"
    ])

    start_pyui()

    set_led_trigger(
        "mmc0"
    )

    log.info(
        f"Update process started on {PLATFORM}"
    )

    log.info(
        "Firmware: "
        + read_sysfs(
            "/etc/version",
            "unknown"
        )
    )

    log.info(
        "Current spruce version: "
        + read_sysfs(
            VERSION_FILE,
            "unknown"
        )
    )

    log.info(
        f"PATH: {os.environ.get('PATH', '')}"
    )

    log.info(
        "LD_LIBRARY_PATH: "
        + os.environ.get(
            "LD_LIBRARY_PATH",
            ""
        )
    )

    ui.image_and_text(
        LOGO,
        35,
        25,
        "Preparing update..."
    )

    read_only_check()

    if not check_sd_health():
        sys.exit(1)

    # ------------------------------------------------------------------
    # Load update queue
    # ------------------------------------------------------------------

    updates = load_queue()

    if updates is None:

        fail(
            "Invalid OTA update queue."
        )

    if not updates:

        fail(
            "No OTA updates are queued."
        )

    log.info(
        f"OTA queue contains "
        f"{len(updates)} update(s)"
    )

    for index, update in enumerate(
        updates,
        start=1
    ):

        log.info(
            f"Queue {index}: "
            f"{update['type']} -> "
            f"{update['version']} "
            f"({update['filename']})"
        )

    # ------------------------------------------------------------------
    # Validate every archive BEFORE modifying the installation
    # ------------------------------------------------------------------

    for index, update in enumerate(
        updates,
        start=1
    ):

        archive = update["path"]

        if not os.path.isfile(archive):

            fail(
                f"Required update file is missing:\n"
                f"{update['filename']}"
            )

        update_type = update["type"]

        log.info(
            f"Validating archive "
            f"{index}/{len(updates)}: "
            f"{archive}"
        )

        ui.image_and_text(
            LOGO,
            35,
            25,
            f"Verifying update {index} of {len(updates)}..."
        )

        if not verify_checksum(
            archive,
            update["checksum"]
        ):

            fail(
                f"Update file failed verification:\n"
                f"{update['filename']}\n"
                "Run 'Check for Updates' to download it again."
            )

        if update_type == "FULL":

            valid = verify_full_archive(
                archive
            )

        else:

            valid = verify_incremental_archive(
                archive
            )

        if not valid:

            fail(
                f"Invalid update archive:\n"
                f"{update['filename']}"
            )

    # ------------------------------------------------------------------
    # Battery check
    # ------------------------------------------------------------------

    battery = int(
        read_sysfs(
            f"{BATTERY_PATH}/capacity",
            "100"
        )
    )

    charging = read_sysfs(
        f"{BATTERY_PATH}/status",
        "Unknown"
    )

    log.info(
        f"Battery: {battery}% ({charging})"
    )

    if (
        battery < 20
        and charging == "Discharging"
    ):

        fail(
            "Battery too low for update.\n"
            "Please charge to at least 20% or "
            "plug in your device."
        )

    # ------------------------------------------------------------------
    # Determine whether this is a full or incremental operation
    # ------------------------------------------------------------------

    full_updates = [
        update
        for update in updates
        if update["type"] == "FULL"
    ]

    incremental_updates = [
        update
        for update in updates
        if update["type"] in (
            "DIFF",
            "DIFF_NIGHTLY"
        )
    ]

    if full_updates and incremental_updates:

        fail(
            "Invalid OTA queue: "
            "full and incremental updates cannot "
            "be mixed."
        )

    is_full = bool(
        full_updates
    )

    if not is_full:

        chain_error = validate_incremental_chain(
            incremental_updates,
            read_sysfs(
                VERSION_FILE,
                ""
            )
        )

        if chain_error:

            fail(
                chain_error
            )

    # ------------------------------------------------------------------
    # Preserve flags before installation
    # ------------------------------------------------------------------

    developer_mode = flag_check(
        "developer_mode"
    )

    tester_mode = flag_check(
        "tester_mode"
    )

    beta = flag_check(
        "beta"
    )

    # ------------------------------------------------------------------
    # Stop services before touching the installation
    # ------------------------------------------------------------------

    kill_network_services()

    # ------------------------------------------------------------------
    # Backup ONCE, regardless of update type
    # ------------------------------------------------------------------

    ui.image_and_text(
        LOGO,
        35,
        25,
        "Backing up your data..."
    )

    if not run_backup():

        fail(
            "Backup failed. Update cancelled."
        )

    set_led_trigger(
        "heartbeat"
    )

    subprocess.run([
        "sync"
    ])

    # ------------------------------------------------------------------
    # FULL UPDATE
    # ------------------------------------------------------------------

    if is_full:

        update = updates[0]

        log.info(
            f"Applying full update: "
            f"{update['version']}"
        )

        if not run_full_cleanup():

            fail(
                "SD card cleanup failed."
            )

        subprocess.run([
            "sync"
        ])

        os.chdir(
            SD_ROOT
        )

        ui.image_and_text(
            LOGO,
            35,
            25,
            "Applying full update. "
            "This should take around 10 minutes..."
        )

        result = extract_with_progress(
            update["path"],
            f"spruce {update['version']}"
        )

        if result != 0:

            fail(
                "Full update extraction failed. "
                "Check updater.log for details."
            )

        log.info(
            "Full update extracted successfully"
        )

        final_version = update["version"]

    # ------------------------------------------------------------------
    # INCREMENTAL UPDATE CHAIN
    # ------------------------------------------------------------------

    else:

        final_version = None

        total_updates = len(
            incremental_updates
        )

        for index, update in enumerate(
            incremental_updates,
            start=1
        ):

            archive = update["path"]
            version = update["version"]

            log.info(
                f"Applying incremental update "
                f"{index}/{total_updates}: "
                f"{version}"
            )

            ui.image_and_text(
                LOGO,
                35,
                25,
                f"Applying update "
                f"{index} of {total_updates}..."
            )

            # Delete only the files specifically listed by
            # this incremental archive.

            if not apply_incremental_deletions(
                archive
            ):

                fail(
                    f"Could not apply deletion list "
                    f"for update {version}."
                )

            subprocess.run([
                "sync"
            ])

            os.chdir(
                SD_ROOT
            )

            result = extract_with_progress(
                archive,
                f"spruce {version}",
                exclude=(
                    ".ota_manifest",
                    ".ota_delete"
                )
            )

            if result != 0:

                fail(
                    f"Incremental update {version} failed "
                    f"(7zr exit code {result}). Run the "
                    "EZ Updater app to retry, or switch the "
                    "OTA update type to Full."
                )

            subprocess.run([
                "sync"
            ])

            log.info(
                f"Incremental update applied: "
                f"{version}"
            )

            final_version = version

    # ------------------------------------------------------------------
    # Verify resulting installation
    # ------------------------------------------------------------------

    required_dirs = (
        ".tmp_update",
        "spruce",
        "miyoo",
        "miyoo355",
        "trimui"
    )

    for directory in required_dirs:

        path = (
            f"{SD_ROOT}/{directory}"
        )

        if (
            not os.path.isdir(path)
            or not os.listdir(path)
        ):

            fail(
                f"Update extraction incomplete: "
                f"{directory}"
            )

    log.info(
        "Update extraction completed successfully"
    )

    # Confirm the version file actually contains
    # the expected version.

    installed_version = read_sysfs(
        VERSION_FILE,
        ""
    )

    log.info(
        f"Expected final version: {final_version}"
    )

    log.info(
        f"Installed version: {installed_version}"
    )

    if (
        installed_version
        and version_base(installed_version)
        != version_base(final_version)
    ):

        log.warning(
            f"Version file ({installed_version}) does not "
            f"match the expected update version "
            f"({final_version})."
        )

    ui.image_and_text(
        LOGO,
        35,
        25,
        f"Now using spruce {final_version}"
    )

    time.sleep(3)

    # ------------------------------------------------------------------
    # Delete archives ONLY after the complete sequence succeeded
    # ------------------------------------------------------------------

    delete_update_files(
        updates
    )

    subprocess.run([
        "sync"
    ])

    # ------------------------------------------------------------------
    # Restore backup ONCE, regardless of update type
    # ------------------------------------------------------------------

    ui.image_and_text(
        LOGO,
        35,
        25,
        "Restoring your data..."
    )

    if not run_restore():

        fail(
            "Update applied, but data restore failed. "
            "Check updater.log."
        )

    subprocess.run([
        "sync"
    ])

    # ------------------------------------------------------------------
    # Restore flags
    # ------------------------------------------------------------------

    restore_flags(
        developer_mode,
        tester_mode,
        beta
    )

    # ------------------------------------------------------------------
    # Cleanup temporary OTA data
    # ------------------------------------------------------------------

    try:

        subprocess.run([
            "rm",
            "-rf",
            f"{OTA_TMP_DIR}/delete_manifest"
        ])

        os.remove(
            QUEUE_FILE
        )

    except OSError:
        pass

    subprocess.run([
        "sync"
    ])

    # ------------------------------------------------------------------
    # Shutdown / reboot
    # ------------------------------------------------------------------

    if PLATFORM == "A30":

        ui.image_and_text(
            LOGO,
            35,
            25,
            "Update complete. Shutting down..."
            " You will need to manually power back on."
        )

    else:

        ui.image_and_text(
            LOGO,
            35,
            25,
            "Update complete. Rebooting..."
        )

    time.sleep(5)

    subprocess.Popen(
        [
            "sh",
            "-c",
            f". {SD_ROOT}/spruce/scripts/"
            f"helperFunctions.sh && vibrate"
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    stop_pyui()

    poweroff = (
        f"{SD_ROOT}/spruce/scripts/"
        "save_poweroff.sh"
    )

    if PLATFORM == "A30":

        os.execv(
            "/bin/sh",
            [
                "/bin/sh",
                poweroff
            ]
        )

    else:

        os.execv(
            "/bin/sh",
            [
                "/bin/sh",
                poweroff,
                "--reboot"
            ]
        )


# ---------------------------------------------------------------------------
# Network services
# ---------------------------------------------------------------------------

def kill_network_services():

    log.info(
        "Killing network services"
    )

    result = run([
        "sh",
        "-c",
        f". {SD_ROOT}/spruce/scripts/"
        f"helperFunctions.sh && "
        f"get_ssh_service_name"
    ])

    ssh = (
        result.stdout.strip()
        if (
            result.returncode == 0
            and result.stdout.strip()
        )
        else "dropbearmulti"
    )

    killall(
        ssh,
        "smbd",
        "sftpgo",
        "syncthing",
        "darkhttpd"
    )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":

    try:
        main()

    except Exception:

        log.exception(
            "Updater crashed"
        )

        ui.image_and_text(
            BAD_IMG,
            35,
            25,
            "Updater error! Check updater.log"
        )

        time.sleep(5)

        sys.exit(1)