#!/usr/bin/env python3
"""
spruceOS EZ Updater — replaces updater.sh.
Expects to be launched from launch.sh which sources helperFunctions.sh,
so all platform env vars (PLATFORM, SD_DEV, BATTERY, LED_PATH, etc.) are set.
"""

import glob
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
LOG_LOCATION = f"{SD_ROOT}/Saves/spruce/updater.log"
FLAGS_DIR = f"{SD_ROOT}/spruce/flags"
LOGO = f"{APP_DIR}/updater.png"
BAD_IMG = f"{SD_ROOT}/spruce/imgs/notfound.png"
CONFIG_FILE = f"{SD_ROOT}/Saves/spruce/spruce-config.json"
VERSION_FILE = f"{SD_ROOT}/spruce/spruce"
APP_CONFIG = f"{APP_DIR}/config.json"

PERFORM_DELETION = True  # debug: set False to skip file cleanup
DELETE_UPDATE = True      # debug: set False to keep update .7z files

# Read platform vars from environment (set by helperFunctions.sh)
PLATFORM = os.environ.get("PLATFORM", "MiyooMini")
SD_DEV = os.environ.get("SD_DEV", "/dev/mmcblk0p1")
SD_MOUNTPOINT = os.environ.get("SD_MOUNTPOINT", SD_ROOT)
LED_PATH = os.environ.get("LED_PATH", "not applicable")
BATTERY_PATH = os.environ.get("BATTERY", "/sys/class/power_supply/battery")


# --- Logging ---

def setup_logging():
    os.makedirs(os.path.dirname(LOG_LOCATION), exist_ok=True)
    logger = logging.getLogger("updater")
    logger.setLevel(logging.DEBUG)
    h = logging.FileHandler(LOG_LOCATION, mode="w", encoding="utf-8")
    h.setFormatter(logging.Formatter("%(asctime)s - %(message)s", "%Y-%m-%d %H:%M:%S"))
    logger.addHandler(h)
    return logger

log = setup_logging()


# --- PyUI display (abstract Unix domain socket, no subprocess per message) ---

class PyUiMessenger:
    SOCKET_ADDR = b"\x0050980"  # abstract Unix socket matching PyUI listener

    def send(self, msg):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(0.5)
            s.connect(self.SOCKET_ADDR)
            s.sendall((msg + "\n").encode("utf-8"))
            s.close()
        except Exception:
            pass

    def image_and_text(self, image, size, img_y, text, text_y=75):
        self.send(json.dumps({"cmd": "IMAGE_AND_TEXT",
            "args": [image, text, str(size), str(img_y), str(text_y)]}))

    def progress_bar(self, text, percent, bottom=""):
        args = [text, str(percent)]
        if bottom:
            args.append(bottom)
        self.send(json.dumps({"cmd": "TEXT_WITH_PERCENTAGE_BAR", "args": args}))

ui = PyUiMessenger()


# --- Small helpers ---

def run(cmd, **kw):
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    if isinstance(cmd, str):
        kw["shell"] = True
    return subprocess.run(cmd, **kw)

def killall(*names, signal="-9"):
    for n in names:
        run(["killall", signal, n])

def flag_check(name):
    return any(os.path.exists(p) for p in (
        f"{FLAGS_DIR}/{name}", f"{FLAGS_DIR}/{name}.lock", f"/tmp/{name}.lock"))

def flag_add(name, tmp=False):
    dest = "/tmp" if tmp else FLAGS_DIR
    os.makedirs(dest, exist_ok=True)
    Path(f"{dest}/{name}.lock").touch()

def flag_remove(name):
    for p in (f"{FLAGS_DIR}/{name}.lock", f"/tmp/{name}.lock"):
        try: os.remove(p)
        except OSError: pass

def get_config_value(key_path, default=""):
    try:
        r = run(["jq", "-r", f'{key_path} // "{default}"', CONFIG_FILE])
        return r.stdout.strip() if r.returncode == 0 else default
    except Exception:
        return default

def read_sysfs(path, default=""):
    try: return Path(path).read_text().strip()
    except OSError: return default

def set_led_trigger(trigger):
    if LED_PATH != "not applicable":
        try: Path(f"{LED_PATH}/trigger").write_text(trigger)
        except OSError: pass

def parse_version(v):
    try: return tuple(int(x) for x in v.split("."))
    except (ValueError, AttributeError): return (0,)

def find_update_file():
    matches = glob.glob(f"{SD_ROOT}/spruceV*.7z")
    if not matches:
        return None
    def key(p):
        m = re.search(r"spruceV([\d.]+)", p)
        return tuple(int(x) for x in m.group(1).split(".")) if m else (0,)
    return sorted(matches, key=key)[-1]


# --- PyUI lifecycle ---

def start_pyui():
    run(["ifconfig", "lo", "up"])
    run(["ifconfig", "lo", "127.0.0.1"])
    if run(["pgrep", "-f", "sgDisplayRealtimePort"]).returncode == 0:
        return
    listener = f"{SD_ROOT}/App/PyUI/realtime_message_network_listener.txt"
    try: os.remove(listener)
    except OSError: pass
    subprocess.Popen([f"{SD_ROOT}/App/PyUI/launch.sh", "-msgDisplayRealtimePort", "50980"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    while not os.path.exists(listener):
        time.sleep(0.1)

def stop_pyui():
    r = run(["pgrep", "-f", "sgDisplayRealtimePort"])
    if r.returncode == 0:
        ui.send(json.dumps({"cmd": "EXIT_APP", "args": []}))
        time.sleep(0.5)
        for pid in r.stdout.strip().split():
            run(["kill", pid])
        time.sleep(1)


# --- SD card checks ---

def read_only_check():
    log.info("Performing read-only check")
    os.makedirs(FLAGS_DIR, exist_ok=True)
    test_file = f"{FLAGS_DIR}/test-{int(time.time())}"
    try:
        Path(test_file).write_text("testing!")
        if Path(test_file).read_text() != "testing!":
            log.warning("SD card likely read-only (data mismatch)")
            return
        os.remove(test_file)
    except OSError:
        log.warning("SD card likely read-only (write failed)")
        return

    for line in run(["mount"]).stdout.splitlines():
        if SD_DEV in line and "(ro" in line:
            log.warning("SD card mounted RO, attempting remount")
            run(["mount", "-o", "remount,rw", SD_DEV, SD_MOUNTPOINT])
            break

def check_sd_health():
    test_file = f"{SD_ROOT}/.sd_test_{os.getpid()}"
    try:
        Path(test_file).write_text("test")
        ok = Path(test_file).read_text() == "test"
        os.remove(test_file)
        if not ok:
            ui.image_and_text(BAD_IMG, 35, 25, "SD card error: Read failed")
            time.sleep(5)
            return False
    except OSError:
        ui.image_and_text(BAD_IMG, 35, 25, "SD card error: Write failed")
        time.sleep(5)
        return False

    try:
        st = os.statvfs(SD_ROOT)
        if (st.f_bavail * st.f_frsize) // 1024 < 1024:
            ui.image_and_text(BAD_IMG, 35, 25, "SD card error: No free space")
            time.sleep(5)
            return False
    except OSError:
        ui.image_and_text(BAD_IMG, 35, 25, "SD card error: Cannot check space")
        time.sleep(5)
        return False

    log.info("SD card is healthy.")
    return True


# --- Archive verification & extraction ---

def verify_7z_content(archive):
    result = run(["7zr", "l", archive])
    if result.returncode != 0:
        return False
    listing = result.stdout
    missing = [d for d in (".tmp_update", "App", "spruce")
               if not re.search(rf"^.*D.*\s{re.escape(d)}$", listing, re.MULTILINE)]
    if missing:
        log.error(f"Missing directories in archive: {' '.join(missing)}")
        return False
    return True

def extract_with_progress(archive):
    # Count files
    r = run(["7zr", "l", "-scsUTF-8", archive])
    total = sum(1 for ln in r.stdout.splitlines() if re.match(r"^\s*\d{4}-", ln)) if r.returncode == 0 else 1
    total = max(total, 1)
    log.info(f"Total files in archive: {total}")

    count = 0
    last_pct = -1

    with open(LOG_LOCATION, "a") as errlog:
        proc = subprocess.Popen(
            ["7zr", "x", "-y", "-scsUTF-8", "-bb1", archive],
            stdout=subprocess.PIPE, stderr=errlog, text=True, bufsize=1)

        for line in proc.stdout:
            name = line.strip().lstrip("- ")
            if not name:
                continue
            count += 1
            pct = count * 100 // total
            if pct != last_pct or count == total:
                ui.progress_bar(name, pct, f"{count} / {total} files")
                last_pct = pct

        proc.wait()
    return proc.returncode


# --- Main ---

def fail(msg, code=1):
    log.error(msg)
    ui.image_and_text(BAD_IMG, 35, 25, msg)
    time.sleep(5)
    sys.exit(code)

def main():
    killall("idlemon", "idlemon_mm.sh", signal="-TERM")
    subprocess.run(["sync"])
    start_pyui()
    set_led_trigger("mmc0")

    log.info(f"Update process started on {PLATFORM}")
    log.info(f"Firmware: {read_sysfs('/etc/version', 'unknown')}")
    for cmd in (["ps"], ["mount"], ["ls", "-Al", SD_MOUNTPOINT]):
        r = run(cmd)
        if r.stdout:
            log.info(f"{' '.join(cmd)}:\n{r.stdout}")
    log.info(f"PATH: {os.environ.get('PATH', '')}")
    log.info(f"LD_LIBRARY_PATH: {os.environ.get('LD_LIBRARY_PATH', '')}")

    ui.image_and_text(LOGO, 35, 25, "Checking for update file...")
    read_only_check()

    if not check_sd_health():
        sys.exit(1)

    # Find update file
    update_file = find_update_file()
    if not update_file:
        # Hide updater app when no update file present
        try:
            with open(APP_CONFIG) as f:
                cfg = json.load(f)
            if "label" in cfg:
                cfg["#label"] = cfg.pop("label")
                with open(APP_CONFIG, "w") as f:
                    json.dump(cfg, f, indent=2)
                    f.write("\n")
        except (OSError, json.JSONDecodeError):
            pass
        fail("No update file found")

    log.info(f"Found update file: {update_file}")

    # Battery check
    battery = int(read_sysfs(f"{BATTERY_PATH}/capacity", "100"))
    charging = read_sysfs(f"{BATTERY_PATH}/status", "Unknown")
    log.info(f"Battery: {battery}% ({charging})")

    if battery < 20 and charging == "Discharging":
        fail("Battery too low for update.\nPlease charge to at least 20% or plug in your device, then try again.")

    # Version comparison
    update_version_str = re.search(r"spruceV([\d.]+)", update_file)
    update_version = update_version_str.group(1) if update_version_str else ""
    current_version = read_sysfs(VERSION_FILE, "2.3.0")
    log.info(f"Version: {update_version} vs {current_version}")

    developer_mode = flag_check("developer_mode")
    tester_mode = flag_check("tester_mode")
    skip_check = (developer_mode or tester_mode or
        get_config_value('.menuOptions."Network Settings".otaskipVersionCheck.selected', "True") == "True")
    beta = "-beta" in update_file

    update_ver = parse_version(update_version)
    current_ver = parse_version(current_version)

    if not skip_check:
        if beta and update_ver < current_ver:
            log.info("Beta version lower than current")
            ui.image_and_text(LOGO, 35, 25, "Current version is up to date.")
            time.sleep(5)
            sys.exit(0)
        elif not beta and update_ver <= current_ver:
            if os.path.isdir(f"{SD_ROOT}/.tmp_update") and os.path.isfile(f"{SD_ROOT}/.tmp_update/updater"):
                ui.image_and_text(LOGO, 35, 25, "Current version is up to date.")
                time.sleep(5)
                sys.exit(0)
            else:
                log.info("Bad installation detected, allowing reinstall")
                ui.image_and_text(LOGO, 35, 25, "Detected current installation is invalid. Allowing reinstall.")
                time.sleep(5)

    # Verify archive
    if not os.path.isfile(update_file):
        fail("Update file not found")
    if not verify_7z_content(update_file):
        fail("Invalid update file structure. Update file corrupt or not a spruce update.")

    kill_network_services()

    # Backup
    subprocess.run([f"{SD_ROOT}/App/spruceBackup/spruceBackup.sh"], timeout=300)
    set_led_trigger("heartbeat")

    # Delete old files
    if PERFORM_DELETION:
        deletion_script = f"{APP_DIR}/delete_files.sh"
        ui.image_and_text(LOGO, 35, 25, "Cleaning up your SD card...")
        try:
            os.chmod(deletion_script, 0o777)
            r = run([deletion_script])
            if r.stdout:
                log.info(f"delete_files.sh output:\n{r.stdout}")
            if r.returncode != 0:
                log.warning(f"Deletion script failed with code {r.returncode}")
                ui.image_and_text(LOGO, 35, 25, "Cleanup failed!")
                time.sleep(5)
            else:
                ui.image_and_text(LOGO, 35, 25, "SD card cleaned up...")
                time.sleep(2)
        except OSError:
            log.warning("Deletion script missing")
            ui.image_and_text(LOGO, 35, 25, "Cleanup skipped!")
            time.sleep(5)
    else:
        log.info("Skipping deletion process")
        ui.image_and_text(LOGO, 35, 25, "Skipping file deletion...")
        time.sleep(5)

    subprocess.run(["sync"])

    # Extract
    os.chdir(SD_ROOT)
    log.info(f"Extracting: {update_file}")
    read_only_check()
    ui.image_and_text(LOGO, 35, 25, "Applying update. This should take around 10 minutes...")

    ret = extract_with_progress(update_file)
    if ret != 0:
        log.warning("Extraction completed with warnings")
        ui.image_and_text(LOGO, 35, 25, "Update completed with warnings. Check the update log for details.")
    else:
        log.info("Extraction completed successfully")
        ui.image_and_text(LOGO, 35, 25, "Update completed!")

    subprocess.run(["sync"])
    time.sleep(5)

    # Verify extraction
    for d in (".tmp_update", "spruce", "miyoo", "miyoo355", "trimui"):
        p = f"{SD_ROOT}/{d}"
        if not os.path.isdir(p) or not os.listdir(p):
            fail(f"Update extraction incomplete: {d}")

    log.info("Update extracted successfully")
    ui.image_and_text(LOGO, 35, 25, f"Now using spruce {update_version}")
    time.sleep(5)

    # Delete update files
    if DELETE_UPDATE:
        log.info("Deleting all update files")
        for f in glob.glob(f"{SD_ROOT}/spruceV*.7z"):
            try: os.remove(f)
            except OSError: pass
        log.info("All update files deleted")

    subprocess.run(["sync"])
    subprocess.run([f"{SD_ROOT}/App/spruceRestore/spruceRestore.sh"], timeout=300)

    # Restore flags
    if developer_mode:
        os.makedirs(FLAGS_DIR, exist_ok=True)
        flag_add("developer_mode")
    if tester_mode:
        flag_remove("developer_mode")
        flag_add("tester_mode")
    if beta:
        Path(f"{FLAGS_DIR}/beta").touch()

    # Shutdown/reboot
    if PLATFORM == "A30":
        ui.image_and_text(LOGO, 35, 25, "Update complete. Shutting down... You will need to manually power back on.")
    else:
        ui.image_and_text(LOGO, 35, 25, "Update complete. Rebooting...")

    time.sleep(5)
    subprocess.Popen(["sh", "-c", f". {SD_ROOT}/spruce/scripts/helperFunctions.sh && vibrate"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    stop_pyui()

    poweroff = f"{SD_ROOT}/spruce/scripts/save_poweroff.sh"
    if PLATFORM == "A30":
        os.execv("/bin/sh", ["/bin/sh", poweroff])
    else:
        os.execv("/bin/sh", ["/bin/sh", poweroff, "--reboot"])


def kill_network_services():
    log.info("Killing network services")
    r = run(["sh", "-c", f". {SD_ROOT}/spruce/scripts/helperFunctions.sh && get_ssh_service_name"])
    ssh = r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else "dropbearmulti"
    killall(ssh, "smbd", "sftpgo", "syncthing", "darkhttpd")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        log.exception("Updater crashed")
        ui.image_and_text(BAD_IMG, 35, 25, "Updater error! Check updater.log")
        time.sleep(5)
        sys.exit(1)
