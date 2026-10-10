"""Clock and timezone sync for spruce, run by timeFunctions.sh once the network is up.

    timesync.py clock [--again]       set the clock from NTP, or from an HTTP Date header
    timesync.py timezone [--again]    in auto mode, set the zone from the network location

Each runs once per boot; --again runs it anyway (the user asked, in Time Settings).
Log lines go to stdout as "LOG <message>" or "VLOG <message>" (verbose) for
log_message. Everything here has its own timeouts, so no timeout(1), ntpd or curl.
"""
import email.utils
import http.client
import json
import os
import re
import socket
import struct
import subprocess
import sys
import time
import urllib.request

VERSION_FILE = "/mnt/SDCARD/spruce/spruce"
PYUI_CONFIG = "/mnt/SDCARD/App/PyUI/py-ui-config.json"
SHARED_CONFIG = "/mnt/SDCARD/Saves/spruce/shared-system.json"
ZONEINFO_DIR = "/mnt/SDCARD/spruce/zoneinfo"
CLOCK_DONE_FLAG = "/tmp/time_sync_done"
TZ_DONE_FLAG = "/tmp/timezone_auto_done"

# These handhelds have no battery-backed RTC, or one that drifts: a cold boot can
# start years in the past, where every TLS certificate reads as not yet valid.
# The clock cannot honestly predate the build reading it, and five years past
# that it is garbage rather than merely unset.
FALLBACK_FLOOR = 1735689600  # 2025-01-01
MAX_AHEAD = 5 * 365 * 86400
NTP_SERVERS = ("pool.ntp.org", "time.cloudflare.com")
NTP_EPOCH_OFFSET = 2208988800
# Plain HTTP needs no valid clock, which breaks the circle when UDP 123 is blocked.
HTTP_DATE_URLS = ("http://www.google.com/generate_204", "http://detectportal.firefox.com/success.txt")
# Plain-HTTP providers first: they work while the clock is still wrong.
TZ_PROVIDERS = (
    ("http://ip-api.com/json/?fields=timezone", "json"),
    ("http://ipwho.is/?fields=timezone.id", "jsonid"),
    ("https://ipapi.co/timezone", "text"),
    ("https://ipinfo.io/timezone", "text"),
    ("http://worldtimeapi.org/api/ip", "json"),
)
ZONE_NAME = re.compile(r"^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)+$")


def log(message, verbose=False):
    print(("VLOG " if verbose else "LOG ") + message, flush=True)


def utc(t):
    return time.strftime("%a %b %d %H:%M:%S UTC %Y", time.gmtime(t))


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def sync_enabled():
    # Fails open: only an explicit false turns it off, because a wrongly skipped
    # sync leaves every HTTPS feature failing with a certificate error.
    config = read_json(PYUI_CONFIG)
    return not (isinstance(config, dict) and config.get("syncTimeViaNetwork") is False)


def floor():
    try:
        return max(int(os.path.getmtime(VERSION_FILE)), FALLBACK_FLOOR)
    except OSError:
        return FALLBACK_FLOOR


def plausible(t):
    low = floor()
    return low <= t < low + MAX_AHEAD


def once(flag, again):
    """True when this should run now; marks it done for the rest of the boot."""
    if os.path.exists(flag) and not again:
        return False
    open(flag, "w").close()
    return True


def ntp_time(server):
    request = b"\x1b" + 47 * b"\0"
    for family, kind, proto, _, address in socket.getaddrinfo(server, 123, type=socket.SOCK_DGRAM):
        with socket.socket(family, kind, proto) as s:
            s.settimeout(5)
            sent = time.time()
            s.sendto(request, address)
            reply = s.recv(48)
            received = time.time()
        if len(reply) < 48:
            continue
        seconds, fraction = struct.unpack("!II", reply[40:48])
        if seconds == 0:
            continue
        return seconds - NTP_EPOCH_OFFSET + fraction / 2**32 + (received - sent) / 2
    return None


def http_date_time(url):
    host, _, path = url.split("://", 1)[1].partition("/")
    connection = http.client.HTTPConnection(host, timeout=8)
    try:
        connection.request("HEAD", "/" + path)
        date = connection.getresponse().getheader("Date")
    finally:
        connection.close()
    return email.utils.parsedate_to_datetime(date).timestamp() if date else None


def network_time():
    """(time, source) from the first NTP server or HTTP Date header that answers."""
    for server in NTP_SERVERS:
        try:
            t = ntp_time(server)
        except (OSError, ValueError):
            continue
        if t and plausible(t):
            return t, server
    for url in HTTP_DATE_URLS:
        try:
            t = http_date_time(url)
        except (OSError, ValueError, http.client.HTTPException):
            continue
        if t and plausible(t):
            return t, url.split("/")[2] + " response headers"
    return None, None


def set_clock(t):
    time.clock_settime(time.CLOCK_REALTIME, t)
    # Best effort: most of these boards have no writable RTC.
    subprocess.run(["hwclock", "-w"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def sync_clock(again):
    if not sync_enabled():
        # Some games read the system clock, so a user may hold it somewhere on purpose.
        log("Time sync: turned off in Time Settings, leaving the clock alone", True)
        return 0
    now = time.time()
    if plausible(now):
        # Still worth one look per boot: an A30 that keeps time through power-off ran
        # three hours slow.
        if not once(CLOCK_DONE_FLAG, again):
            return 0
        t, source = network_time()
        if t is None:
            log(f"Time sync: no time server answered, clock left at {utc(now)}", True)
            return 0
        drift = t - time.time()
        if abs(drift) >= 2:
            set_clock(t)
            log(f"Time sync: clock was {drift:+.0f}s off, set from {source}", abs(drift) < 60)
        return 0
    log(f"Time sync: clock reads {utc(now)}, which predates this build - repairing")
    t, source = network_time()
    if t is None:
        log("Time sync: could not determine the time - HTTPS will keep failing with 'certificate is not yet valid'")
        return 1
    set_clock(t)
    open(CLOCK_DONE_FLAG, "w").close()
    log(f"Time sync: clock set to {utc(t)} from {source}")
    return 0


def timezone_mode(shared):
    # A zone saved with no mode predates the setting and was picked by hand.
    mode = shared.get("timezoneMode")
    if mode in ("auto", "manual"):
        return mode
    return "manual" if shared.get("timezone") else "auto"


def valid_zone(name):
    return (isinstance(name, str) and len(name) <= 64 and ZONE_NAME.match(name)
            and ".." not in name.split("/") and os.path.isfile(os.path.join(ZONEINFO_DIR, name)))


def zone_from(url, kind):
    with urllib.request.urlopen(url, timeout=15) as response:
        body = response.read(4096).decode("utf-8", "replace")
    if kind == "text":
        zone = body.strip().splitlines()[0].strip() if body.strip() else ""
    else:
        data = json.loads(body)
        zone = data.get("timezone")
        if kind == "jsonid":
            zone = zone.get("id") if isinstance(zone, dict) else None
    return zone if valid_zone(zone) else None


def write_shared(shared):
    # Whole file or nothing: PyUI reads it at any moment.
    folder = os.path.dirname(SHARED_CONFIG)
    os.makedirs(folder, exist_ok=True)
    tmp = os.path.join(folder, f".shared-system.json.tmp.{os.getpid()}")
    with open(tmp, "w") as f:
        json.dump(shared, f, indent=4)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, SHARED_CONFIG)
    os.sync()


def sync_timezone(again):
    if os.path.exists(TZ_DONE_FLAG) and not again:
        return 0
    if not os.path.isdir(ZONEINFO_DIR):
        return 0
    # The Pixel 2 keeps its zone in its own system layer.
    if os.environ.get("PLATFORM") == "Pixel2":
        return 0
    if not sync_enabled():
        log("Timezone: network sync turned off in Time Settings, leaving the zone alone", True)
        return 0
    shared = read_json(SHARED_CONFIG)
    if not isinstance(shared, dict):
        shared = {}
    if timezone_mode(shared) != "auto":
        log("Timezone: set by hand, leaving it alone", True)
        return 0

    found = None
    for url, kind in TZ_PROVIDERS:
        try:
            found = zone_from(url, kind)
        except (OSError, ValueError, AttributeError, IndexError, http.client.HTTPException):
            found = None
        if found:
            log(f"Timezone: {found} from {url.split('/')[2]}", True)
            break
    if not found:
        log("Timezone: no geolocation provider answered, leaving the zone alone")
        return 1

    current = shared.get("timezone")
    if current == found:
        log(f"Timezone: already {found}", True)
    else:
        shared["timezone"] = found
        shared["timezoneMode"] = "auto"
        try:
            write_shared(shared)
        except OSError:
            log(f"Timezone: could not write {SHARED_CONFIG}")
            return 1
        log(f"Timezone: set to {found} automatically" + (f" (was {current})" if current else ""))
    open(TZ_DONE_FLAG, "w").close()
    return 0


def main(argv):
    if len(argv) < 2 or argv[1] not in ("clock", "timezone"):
        sys.exit(__doc__)
    again = "--again" in argv[2:]
    return sync_clock(again) if argv[1] == "clock" else sync_timezone(again)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
