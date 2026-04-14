#!/bin/sh
# scrape_covers.sh — fetch cover art for a GVU media folder
#
# Usage: scrape_covers.sh <folder_path> [tmdb_api_key] [--movie]
#
# Saves cover.jpg to <folder_path>/cover.jpg.
#
# TV show mode (default):
#   Season folder detection: if basename matches "Season N" / "S01" patterns,
#   the parent directory name is used as the show/search name.
#   Sources: TMDB (multi search) → TVMaze fallback.
#
# Movie mode (--movie flag):
#   Uses TMDB /search/movie endpoint.  Year is stripped from folder name for
#   search but passed as the year= param when present (e.g. "Title (1985)").
#   TVMaze is skipped (TV-only database).
#
# Writes progress messages to stdout.
# Exit 0 = success, non-zero = failure.
#
# On-device dependencies: wget, sed, tr, grep, basename, dirname
#   (all standard BusyBox utilities on SpruceOS)

set -e

FOLDER="$1"
TMDB_KEY="${2:-}"
MOVIE_MODE="${3:-}"

TMDB_SEARCH_MULTI="http://api.themoviedb.org/3/search/multi"
TMDB_SEARCH_MOVIE="http://api.themoviedb.org/3/search/movie"
TMDB_IMG_BASE="http://image.tmdb.org/t/p/w500"
TVMAZE_SEARCH="http://api.tvmaze.com/search/shows"

# Use plain 'wget' from PATH.  SpruceOS sets PATH to prefer
# /mnt/SDCARD/spruce/bin/wget (GNU wget 1.20.3) over the old BusyBox wget,
# and sets LD_LIBRARY_PATH to include the platform lib dir (e.g. spruce/a30/lib)
# where GNU wget's libpcre dependency lives.  Both are inherited by this script.
WGET="wget"

if [ -z "$FOLDER" ]; then
    echo "Usage: scrape_covers.sh <folder_path> [tmdb_key]" >&2
    exit 1
fi

# -------------------------------------------------------------------------
# Determine search name and optional year
# -------------------------------------------------------------------------
name=$(basename "$FOLDER")
season_num=""
year_param=""

if [ "$MOVIE_MODE" = "--movie" ]; then
    # Extract year if present: "Title (1985)" → year_param="&year=1985"
    year=$(echo "$name" | sed -n 's/.*(\([0-9]\{4\}\)).*/\1/p')
    if [ -n "$year" ]; then
        year_param="&year=${year}"
    fi
    # Strip year and surrounding whitespace/parens for a clean search query
    name=$(echo "$name" | sed 's/[[:space:]]*([0-9]\{4\})[[:space:]]*//' \
                        | sed 's/[[:space:]]*$//')
    echo "Movie search: '$name'${year:+ (year=$year)}"
else
    # Season folder detection for TV shows
    if echo "$name" | grep -qiE '^(season[ _-]*[0-9]+|s[0-9]{1,2})$'; then
        parent=$(dirname "$FOLDER")
        show=$(basename "$parent")
        echo "Season folder detected: '$name' — using parent name: '$show'"
        # Extract numeric season number, stripping leading zeros
        season_num=$(echo "$name" | sed -n 's/^[Ss]eason[[:space:]_-]*0*\([1-9][0-9]*\)$/\1/p')
        if [ -z "$season_num" ]; then
            season_num=$(echo "$name" | sed -n 's/^[Ss]0*\([1-9][0-9]*\)$/\1/p')
        fi
        name="$show"
    fi
    echo "Searching for: $name"
fi

# -------------------------------------------------------------------------
# URL-encode the query (spaces and common punctuation)
# -------------------------------------------------------------------------
urlencode() {
    printf '%s' "$1" | sed \
        's/ /%20/g; s/!/%21/g; s/"/%22/g; s/#/%23/g; s/&/%26/g;
         s/(/%28/g; s/)/%29/g; s/+/%2B/g; s/,/%2C/g; s/:/%3A/g;
         s/;/%3B/g; s/=/%3D/g; s/?/%3F/g; s/@/%40/g'
}
query=$(urlencode "$name")

# -------------------------------------------------------------------------
# Temp file for API responses
# -------------------------------------------------------------------------
tmpfile="/tmp/gvu_scrape_$$.json"
tmpimg="/tmp/gvu_cover_$$.jpg"
tmpseasons="/tmp/gvu_seasons_$$.json"
# On any exit (normal or abnormal), clean up temps and ensure the sentinel
# is always written so GVU never gets stuck showing the progress overlay.
trap 'rm -f "$tmpfile" "$tmpimg" "$tmpseasons"; [ -f /tmp/gvu_scrape_done ] || echo "error" > /tmp/gvu_scrape_done' EXIT

cover_url=""
show_id=""

# -------------------------------------------------------------------------
# 1. TMDB (primary — requires API key)
# -------------------------------------------------------------------------
if [ -n "$TMDB_KEY" ]; then
    echo "Trying TMDB..."
    if [ "$MOVIE_MODE" = "--movie" ]; then
        url="${TMDB_SEARCH_MOVIE}?api_key=${TMDB_KEY}&query=${query}${year_param}&page=1"
    else
        url="${TMDB_SEARCH_MULTI}?api_key=${TMDB_KEY}&query=${query}&page=1"
    fi
    if $WGET -q --no-check-certificate -T 10 -O "$tmpfile" "$url" 2>/dev/null; then
        # Split on commas so each JSON field is on its own line, then extract
        # the first "poster_path" value (skips "null" entries).
        poster=$(tr ',' '\n' < "$tmpfile" \
                 | grep '"poster_path"' \
                 | head -1 \
                 | sed 's/.*"poster_path":"\([^"]*\)".*/\1/' || true)
        if [ -n "$poster" ] && [ "$poster" != "null" ]; then
            cover_url="${TMDB_IMG_BASE}${poster}"
            echo "TMDB: found poster $poster"
        else
            echo "TMDB: no poster in results"
        fi
    else
        echo "TMDB: request failed (check API key and network)"
    fi
fi

# -------------------------------------------------------------------------
# 2. TVMaze — TV shows only; skipped entirely in movie mode.
#    Always queried for show_id (needed for season art bulk scraping
#    even when TMDB already provided the show cover).  Image URL only used as
#    fallback when TMDB found nothing.
# -------------------------------------------------------------------------
if [ "$MOVIE_MODE" = "--movie" ]; then
    # TVMaze is TV-only — skip it entirely for movies
    if [ -z "$cover_url" ]; then
        echo "ERROR: No cover art found (movie mode requires a TMDB API key)" >&2
        echo "error" > /tmp/gvu_scrape_done
        exit 1
    fi
else
    # -----------------------------------------------------------------------
    # 2. TVMaze — always queried for show_id (needed for season art bulk
    #    scraping even when TMDB already provided the show cover).  Image URL
    #    only used as fallback when TMDB found nothing.
    # -----------------------------------------------------------------------
    echo "Querying TVMaze..."
    url="${TVMAZE_SEARCH}?q=${query}"
    if $WGET -q --no-check-certificate -T 10 -O "$tmpfile" "$url" 2>/dev/null; then
        # Extract show ID for season artwork lookup
        show_id=$(tr ',' '\n' < "$tmpfile" \
                  | grep '"id"' | head -1 \
                  | sed 's/[^0-9]*\([0-9]*\).*/\1/' || true)

        if [ -z "$cover_url" ]; then
            # TMDB found nothing — use TVMaze medium portrait (consistent sizing)
            show_orig=$(tr ',' '\n' < "$tmpfile" \
                        | grep '"medium"' | head -1 \
                        | sed 's/.*"medium":"\([^"]*\)".*/\1/' || true)
            show_orig=$(echo "$show_orig" | sed 's|^https://|http://|')

            # Season-specific artwork (only when in a detected season folder)
            if [ -n "$season_num" ] && [ -n "$show_id" ]; then
                echo "TVMaze: fetching season $season_num artwork for show $show_id"
                seas_url="http://api.tvmaze.com/shows/${show_id}/seasons"
                if $WGET -q --no-check-certificate -T 10 -O "$tmpfile" "$seas_url" 2>/dev/null; then
                    # Anchor to $ because after tr each field ends at EOL.
                    # grep -A 20: "number" and "medium" are ~13 fields apart.
                    orig=$(tr ',' '\n' < "$tmpfile" \
                           | grep -A 20 '"number":'"$season_num"'$' \
                           | grep '"medium"' | head -1 \
                           | sed 's/.*"medium":"\([^"]*\)".*/\1/' || true)
                    orig=$(echo "$orig" | sed 's|^https://|http://|')
                    if [ -n "$orig" ] && [ "$orig" != "null" ]; then
                        cover_url="$orig"
                        echo "TVMaze: found season $season_num artwork"
                    fi
                fi
            fi

            if [ -z "$cover_url" ]; then
                if [ -n "$show_orig" ] && [ "$show_orig" != "null" ]; then
                    cover_url="$show_orig"
                    echo "TVMaze: found show image"
                else
                    echo "TVMaze: no image in results"
                fi
            fi
        else
            echo "TVMaze: show_id=${show_id} (show cover already found via TMDB)"
        fi
    else
        echo "TVMaze: request failed"
    fi
fi

# -------------------------------------------------------------------------
# Download cover image
# -------------------------------------------------------------------------
if [ -z "$cover_url" ]; then
    echo "ERROR: No cover art found for: $name" >&2
    echo "error" > /tmp/gvu_scrape_done
    exit 1
fi

echo "Downloading: $cover_url"
dest="${FOLDER}/cover.jpg"
if $WGET -q --no-check-certificate -T 10 -O "$tmpimg" "$cover_url" 2>/dev/null; then
    mv "$tmpimg" "$dest"
    echo "Saved: $dest"
    # Signal GVU now so the overlay dismisses while season covers scrape
    echo "ok" > /tmp/gvu_scrape_done

    # -------------------------------------------------------------------------
    # Bulk season cover scraping
    # When called on a show folder (not a season subfolder), and TVMaze returned
    # a show ID, fetch individual season artwork for each season subdirectory.
    # -------------------------------------------------------------------------
    if [ -z "$season_num" ] && [ -n "$show_id" ] && [ "$MOVIE_MODE" != "--movie" ]; then
        echo "Fetching season artwork for show $show_id..."
        seas_url="http://api.tvmaze.com/shows/${show_id}/seasons"
        if $WGET -q --no-check-certificate -T 10 -O "$tmpseasons" "$seas_url" 2>/dev/null; then
            for subdir in "$FOLDER"/*/; do
                [ -d "$subdir" ] || continue
                subname=$(basename "${subdir%/}")
                # Detect season pattern and extract number
                snum=""
                if echo "$subname" | grep -qiE '^(season[ _-]*[0-9]+|s[0-9]{1,2})$'; then
                    snum=$(echo "$subname" | sed -n 's/^[Ss]eason[[:space:]_-]*0*\([1-9][0-9]*\)$/\1/p')
                    if [ -z "$snum" ]; then
                        snum=$(echo "$subname" | sed -n 's/^[Ss]0*\([1-9][0-9]*\)$/\1/p')
                    fi
                fi
                [ -z "$snum" ] && continue
                # Skip if cover already exists
                if [ -f "${subdir}cover.jpg" ]; then
                    echo "Season $snum: cover exists, skipping"
                    continue
                fi
                # Find season image URL from seasons JSON
                orig=$(tr ',' '\n' < "$tmpseasons" \
                       | grep -A 20 '"number":'"$snum"'$' \
                       | grep '"medium"' | head -1 \
                       | sed 's/.*"medium":"\([^"]*\)".*/\1/' || true)
                orig=$(echo "$orig" | sed 's|^https://|http://|')
                if [ -z "$orig" ] || [ "$orig" = "null" ]; then
                    echo "Season $snum: no artwork found"
                    continue
                fi
                echo "Season $snum: downloading $orig"
                if $WGET -q --no-check-certificate -T 10 -O "$tmpimg" "$orig" 2>/dev/null; then
                    mv "$tmpimg" "${subdir}cover.jpg"
                    echo "Season $snum: saved ${subdir}cover.jpg"
                else
                    echo "Season $snum: download failed"
                fi
            done
        else
            echo "TVMaze: could not fetch seasons list"
        fi
    fi

    exit 0
else
    echo "ERROR: Download failed: $cover_url" >&2
    echo "error" > /tmp/gvu_scrape_done
    exit 1
fi
