#!/usr/bin/env bash
# sync-to-device.sh — copy every unstaged-modified file onto a mounted
# device (e.g. an SD card), mirroring the repo's relative paths.
#
# Usage:
#   ./sync-to-device.sh <target-dir>
#
# Only files with unstaged changes are copied — i.e. what "git diff
# --name-only" reports, which is exactly the set of tracked files whose
# working-tree content differs from the index and hasn't been `git add`'d
# yet. Deletions are skipped (nothing to copy); untracked new files aren't
# included either, since they have no diff against the index.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <target-dir>" >&2
    exit 1
fi
target="$1"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# --- gather unstaged-modified files ------------------------------------
files=()
while IFS= read -r -d '' f; do
    files+=("$f")
done < <(git diff --no-renames --diff-filter=d -z --name-only)

if [ "${#files[@]}" -eq 0 ]; then
    echo "No unstaged changes to copy."
    exit 0
fi

echo "Unstaged files to copy:"
for f in "${files[@]}"; do
    echo "  $f"
done
echo

# Expand a leading ~
target="${target/#\~/$HOME}"

if [ ! -d "$target" ]; then
    echo "Target directory '$target' does not exist." >&2
    exit 1
fi

# --- copy, mirroring relative paths -------------------------------------
for f in "${files[@]}"; do
    dest="$target/$f"
    mkdir -p "$(dirname "$dest")"
    cp -p "$f" "$dest"
    echo "copied $f -> $dest"
done

echo
echo "Done: copied ${#files[@]} file(s) to $target"
