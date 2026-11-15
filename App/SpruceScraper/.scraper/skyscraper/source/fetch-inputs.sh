#!/usr/bin/env bash
# Download the pinned sources of build-glibc233.sh into INPUTS and check them: the tarballs against
# inputs.tsv, Skyscraper by cloning its tag and comparing the commit with pins.sh.
#
#   skyscraper/build/fetch-inputs.sh
#   INPUTS=/some/dir SKYSCRAPER_REPO=~/ai/git-ro/Gemba/skyscraper skyscraper/build/fetch-inputs.sh
#
# INPUTS defaults to ~/ai/cache/sprucescraper-skyscraper-inputs (a workspace cache: everything in it
# comes back from this script). Files already there are checked, not fetched again.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/pins.sh"
INPUTS=${INPUTS:-$HOME/ai/cache/sprucescraper-skyscraper-inputs}
mkdir -p "$INPUTS"
die() { echo "fetch-inputs: $*" >&2; exit 1; }

while IFS=$'\t' read -r name sum url; do
    case "$name" in '' | '#'*) continue ;; esac
    if [ ! -f "$INPUTS/$name" ]; then
        echo "fetching $name"
        curl -fsSL --retry 3 -o "$INPUTS/$name.part" "$url" || die "download failed: $url"
        mv "$INPUTS/$name.part" "$INPUTS/$name"
    fi
    echo "$sum  $INPUTS/$name" | sha256sum -c --quiet - || die "$name does not match inputs.tsv"
done < "$HERE/inputs.tsv"

if [ ! -f "$INPUTS/$SKYSCRAPER_TARBALL" ]; then
    echo "fetching Skyscraper $SKYSCRAPER_TAG from $SKYSCRAPER_REPO"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    git init -q --bare "$tmp/sky.git"
    git -C "$tmp/sky.git" fetch -q --depth 1 "$SKYSCRAPER_REPO" "refs/tags/$SKYSCRAPER_TAG:refs/tags/$SKYSCRAPER_TAG"
    got=$(git -C "$tmp/sky.git" rev-parse "refs/tags/$SKYSCRAPER_TAG^{commit}")
    [ "$got" = "$SKYSCRAPER_COMMIT" ] || die "tag $SKYSCRAPER_TAG is $got, pins.sh says $SKYSCRAPER_COMMIT"
    git -C "$tmp/sky.git" archive --format=tar --prefix="skyscraper-$SKYSCRAPER_TAG/" "$SKYSCRAPER_COMMIT" |
        gzip -n > "$INPUTS/$SKYSCRAPER_TARBALL.part"
    mv "$INPUTS/$SKYSCRAPER_TARBALL.part" "$INPUTS/$SKYSCRAPER_TARBALL"
fi
# git archive records the commit in the tar header; get-tar-commit-id stops reading after it, so
# gzip's broken pipe is expected and must not fail the pipeline
got=$( { gzip -dc "$INPUTS/$SKYSCRAPER_TARBALL" 2>/dev/null || true; } | git get-tar-commit-id)
[ "$got" = "$SKYSCRAPER_COMMIT" ] || die "$SKYSCRAPER_TARBALL is commit $got, pins.sh says $SKYSCRAPER_COMMIT"

cat > "$INPUTS/README.md" <<EOF
# sprucescraper-skyscraper-inputs

Sources for Spruce Scraper's Skyscraper build (\`APP/SpruceScraper/git/skyscraper/build/build-glibc233.sh\`).
Recreate with \`APP/SpruceScraper/git/skyscraper/build/fetch-inputs.sh\`: the tarballs are checked against
\`skyscraper/build/inputs.tsv\`; \`$SKYSCRAPER_TARBALL\` is \`git archive\` of Skyscraper commit
$SKYSCRAPER_COMMIT (tag $SKYSCRAPER_TAG, $SKYSCRAPER_REPO), checked with \`git get-tar-commit-id\`.
Every build record copies what it used into its own sources/ folder, so this cache can be cleared.
EOF
echo "inputs OK in $INPUTS"
