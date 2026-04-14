#!/usr/bin/env python3
"""
GVU subtitle fetcher — SubDL primary, Podnapisi fallback.

Usage:
  fetch_subtitles.py search   <video_path> <subdl_key> <lang_code>
  fetch_subtitles.py download <provider>   <download_key> <srt_dest>

Search writes:
  /tmp/gvu_sub_results.txt  — pipe-delimited lines:
                               provider|download_key|display_name|lang|downloads|hi
  /tmp/gvu_sub_done         — "ok" or "error: <message>"

Download writes:
  <srt_dest>                — extracted .srt file
  /tmp/gvu_sub_done         — "ok" or "error: <message>"

Requires PYTHONHOME=/mnt/SDCARD/spruce/bin/python in the environment.
All HTTPS calls are delegated to curl (avoids Python SSL cert issues).
"""

import sys
import os
import re
import json
import subprocess
import zipfile
import tempfile
import shutil

CURL         = "/mnt/SDCARD/spruce/bin/curl"
RESULTS_FILE = "/tmp/gvu_sub_results.txt"
DONE_FILE    = "/tmp/gvu_sub_done"
SUBDL_DL_BASE = "https://dl.subdl.com"

# ---------------------------------------------------------------------------
# URL encoding (no urllib to avoid SSL cert path issues)
# ---------------------------------------------------------------------------

def url_encode(s):
    safe = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    out = []
    for c in s:
        if c == " ":
            out.append("+")
        elif c in safe:
            out.append(c)
        else:
            b = c.encode("utf-8")
            out.append("".join("%%%02X" % byte for byte in b))
    return "".join(out)

# ---------------------------------------------------------------------------
# curl helpers
# ---------------------------------------------------------------------------

def curl_get(url, extra_args=None):
    """Run curl GET. Returns (http_status_int, body_str)."""
    cmd = [CURL, "-s", "-w", "\n%{http_code}", "-L",
           "--max-time", "20"]
    if extra_args:
        cmd += extra_args
    cmd.append(url)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        return 0, ""
    parts = r.stdout.rsplit("\n", 1)
    body  = parts[0] if len(parts) > 1 else r.stdout
    code  = 0
    if len(parts) > 1 and parts[1].strip().isdigit():
        code = int(parts[1].strip())
    return code, body


def curl_download(url, dest_path):
    """Download a file to dest_path. Returns True on success."""
    cmd = [CURL, "-s", "-L", "--max-time", "60", "-o", dest_path, url]
    try:
        r = subprocess.run(cmd, timeout=70)
    except subprocess.TimeoutExpired:
        return False
    return (r.returncode == 0
            and os.path.exists(dest_path)
            and os.path.getsize(dest_path) > 100)

# ---------------------------------------------------------------------------
# Filename parsing
# ---------------------------------------------------------------------------

# Tags to strip from titles
_RELEASE_TAGS = re.compile(
    r"\b(720p|1080p|2160p|4K|HDR|SDR|WEBRip|WEB[- ]DL|BluRay|BDRip|DVDRip|"
    r"x264|x265|H\.?264|H\.?265|HEVC|AVC|AAC|AC3|DDP|DTS|FLAC|"
    r"AMZN|HULU|NF|DSNP|ATVP|WEB|HDTV|PROPER|REPACK|EXTENDED|"
    r"YTS|RARBG|YIFY|EAC3|TrueHD)\b",
    re.IGNORECASE,
)
_SXXEXX = re.compile(r"[Ss](\d{1,2})[Ee](\d{1,3})")
_SEASON_DIR = re.compile(r"[Ss]eason\s*\d+|[Ss]\d{1,2}$", re.IGNORECASE)


def parse_filename(video_path):
    """
    Extract (title, season, episode) from a video file path.
    season and episode are ints or None.
    """
    filename  = os.path.basename(video_path)
    stem      = os.path.splitext(filename)[0]
    # Normalise separators
    stem_norm = re.sub(r"[\._]", " ", stem)

    m = _SXXEXX.search(stem_norm)
    if m:
        season   = int(m.group(1))
        episode  = int(m.group(2))
        raw_title = stem_norm[:m.start()].strip()
    else:
        season = episode = None
        raw_title = stem_norm

    # If no season in filename, check parent directory
    if season is None:
        parent_name = os.path.basename(os.path.dirname(video_path))
        pm = _SXXEXX.search(parent_name)
        if pm:
            season  = int(pm.group(1))
            episode = int(pm.group(2))

    # If we found a season but no title, climb directory tree for show name
    if season is not None and not raw_title.strip():
        parent = os.path.basename(os.path.dirname(video_path))
        grand  = os.path.basename(os.path.dirname(os.path.dirname(video_path)))
        if _SEASON_DIR.match(parent):
            raw_title = grand
        else:
            raw_title = parent

    # Strip release tags and excess whitespace
    title = _RELEASE_TAGS.sub(" ", raw_title)
    title = re.sub(r"\s{2,}", " ", title).strip(" -([")
    return title, season, episode

# ---------------------------------------------------------------------------
# SubDL search
# ---------------------------------------------------------------------------

def subdl_search(title, season, episode, lang, api_key):
    """Returns list of result-dicts or None on failure."""
    if not api_key:
        return None

    params = "api_key={}&film_name={}&languages={}".format(
        url_encode(api_key), url_encode(title), url_encode(lang.upper())
    )
    if season is not None:
        params += "&season_number={}&episode_number={}&type=tv".format(season, episode)

    url    = "https://api.subdl.com/api/v1/subtitles?" + params
    code, body = curl_get(url)
    if code != 200:
        print("subdl: HTTP {}".format(code), file=sys.stderr)
        return None

    try:
        data = json.loads(body)
    except json.JSONDecodeError as e:
        print("subdl: JSON parse error:", e, file=sys.stderr)
        return None

    results = []
    for item in data.get("subtitles", []):
        dl_url = item.get("url", "")
        if not dl_url:
            continue
        results.append({
            "provider":     "subdl",
            "download_key": dl_url,
            "display_name": item.get("name", "Unknown")[:80],
            "lang":         item.get("language", lang).lower(),
            "downloads":    int(item.get("downloads", 0)),
            "hi":           1 if item.get("hi") else 0,
        })
    return results if results else None

# ---------------------------------------------------------------------------
# Podnapisi fallback search
# ---------------------------------------------------------------------------

def podnapisi_search(title, season, episode, lang):
    """Returns list of result-dicts or None on failure."""
    params = "keywords={}&language={}".format(url_encode(title), url_encode(lang))
    if season is not None:
        params += "&seasons={}&episodes={}".format(season, episode)

    url = "https://www.podnapisi.net/subtitles/search/?" + params
    code, body = curl_get(url, ["-H", "Accept: application/json"])
    if code != 200:
        print("podnapisi: HTTP {}".format(code), file=sys.stderr)
        return None

    try:
        data = json.loads(body)
    except json.JSONDecodeError as e:
        print("podnapisi: JSON parse error:", e, file=sys.stderr)
        return None

    results = []
    for item in data.get("data", []):
        pid = str(item.get("id", ""))
        if not pid:
            continue
        results.append({
            "provider":     "podnapisi",
            "download_key": pid,
            "display_name": item.get("title", "Unknown")[:80],
            "lang":         item.get("language", lang).lower(),
            "downloads":    int(item.get("downloads_count", 0)),
            "hi":           0,
        })
    return results if results else None

# ---------------------------------------------------------------------------
# ZIP extraction helper
# ---------------------------------------------------------------------------

def extract_best_srt(zip_path, dest_path):
    """
    Extract the best-matching .srt from zip_path to dest_path.
    Prefers files whose name contains the same S##E## as dest_path.
    Falls back to the largest .srt if no episode match is found.
    Returns True on success, False on failure.
    """
    dest_stem = os.path.splitext(os.path.basename(dest_path))[0]
    ep_m = _SXXEXX.search(re.sub(r"[\._]", " ", dest_stem))
    ep_s = int(ep_m.group(1)) if ep_m else None
    ep_e = int(ep_m.group(2)) if ep_m else None

    try:
        with zipfile.ZipFile(zip_path, "r") as z:
            srts = [(name, z.getinfo(name).file_size)
                    for name in z.namelist()
                    if name.lower().endswith(".srt")]
            if not srts:
                print("zip: no .srt files found", file=sys.stderr)
                return False

            best = None
            if ep_s is not None:
                # Prefer a file whose name encodes the same episode number
                candidates = []
                for name, size in srts:
                    m = _SXXEXX.search(re.sub(r"[\._]", " ", os.path.basename(name)))
                    if m and int(m.group(1)) == ep_s and int(m.group(2)) == ep_e:
                        candidates.append((name, size))
                if candidates:
                    candidates.sort(key=lambda x: x[1], reverse=True)
                    best = candidates[0][0]

            if best is None:
                srts.sort(key=lambda x: x[1], reverse=True)
                if ep_s is not None:
                    # No episode-matched file found. Refuse if:
                    # - multiple files (season pack, right episode simply absent), or
                    # - single file but it carries an explicit different episode tag
                    fallback = os.path.basename(srts[0][0])
                    fm = _SXXEXX.search(re.sub(r"[\._]", " ", fallback))
                    wrong_ep = fm and (int(fm.group(1)) != ep_s or int(fm.group(2)) != ep_e)
                    if len(srts) > 1 or wrong_ep:
                        print("zip: no S{:02d}E{:02d} match ({} files)".format(
                            ep_s, ep_e, len(srts)), file=sys.stderr)
                        return False
                best = srts[0][0]

            print("zip: extracting '{}'".format(best), file=sys.stderr)
            with z.open(best) as src, open(dest_path, "wb") as dst:
                shutil.copyfileobj(src, dst)
        return True
    except zipfile.BadZipFile as e:
        print("zip: bad zip file:", e, file=sys.stderr)
        return False

# ---------------------------------------------------------------------------
# write sentinel
# ---------------------------------------------------------------------------

def write_done(msg):
    with open(DONE_FILE, "w") as f:
        f.write(msg + "\n")

# ---------------------------------------------------------------------------
# Search mode
# ---------------------------------------------------------------------------

def do_search(video_path, api_key, lang):
    # Remove stale files
    for path in [RESULTS_FILE, DONE_FILE]:
        try:
            os.remove(path)
        except OSError:
            pass

    title, season, episode = parse_filename(video_path)
    print("search: title='{}' s={} e={} lang={}".format(
        title, season, episode, lang), file=sys.stderr)

    results = None

    # Primary: SubDL
    if api_key:
        results = subdl_search(title, season, episode, lang, api_key)
        if results:
            print("subdl: {} results".format(len(results)), file=sys.stderr)

    # Fallback: Podnapisi
    if not results:
        results = podnapisi_search(title, season, episode, lang)
        if results:
            print("podnapisi: {} results".format(len(results)), file=sys.stderr)

    if not results:
        write_done("error: no subtitles found")
        return

    # Sort by downloads descending
    results.sort(key=lambda r: r["downloads"], reverse=True)

    with open(RESULTS_FILE, "w") as f:
        for r in results[:SUB_RESULT_MAX if hasattr(sys.modules[__name__], 'SUB_RESULT_MAX') else 32]:
            line = "|".join([
                r["provider"],
                r["download_key"],
                r["display_name"],
                r["lang"],
                str(r["downloads"]),
                str(r["hi"]),
            ])
            f.write(line + "\n")

    print("wrote {} results to {}".format(len(results), RESULTS_FILE), file=sys.stderr)
    write_done("ok")

# ---------------------------------------------------------------------------
# Download mode
# ---------------------------------------------------------------------------

def do_download(provider, download_key, srt_dest):
    # Remove stale sentinel
    try:
        os.remove(DONE_FILE)
    except OSError:
        pass

    tmpdir = tempfile.mkdtemp(prefix="gvu_sub_")
    try:
        zip_path = os.path.join(tmpdir, "sub.zip")

        if provider == "subdl":
            url = SUBDL_DL_BASE + download_key
        elif provider == "podnapisi":
            url = "https://www.podnapisi.net/subtitles/{}/download".format(download_key)
        else:
            write_done("error: unknown provider '{}'".format(provider))
            return

        print("download: {}".format(url), file=sys.stderr)
        if not curl_download(url, zip_path):
            write_done("error: download failed")
            return

        if not extract_best_srt(zip_path, srt_dest):
            write_done("error: wrong episode in archive (try another result)")
            return
        print("saved to {}".format(srt_dest), file=sys.stderr)
        write_done("ok")

    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: fetch_subtitles.py search|download ...", file=sys.stderr)
        sys.exit(1)

    mode = sys.argv[1]

    if mode == "search":
        if len(sys.argv) < 5:
            print("Usage: fetch_subtitles.py search <video_path> <subdl_key> <lang>",
                  file=sys.stderr)
            sys.exit(1)
        do_search(sys.argv[2], sys.argv[3], sys.argv[4])

    elif mode == "download":
        if len(sys.argv) < 5:
            print("Usage: fetch_subtitles.py download <provider> <download_key> <srt_dest>",
                  file=sys.stderr)
            sys.exit(1)
        do_download(sys.argv[2], sys.argv[3], sys.argv[4])

    else:
        print("Unknown mode: {}".format(mode), file=sys.stderr)
        sys.exit(1)
