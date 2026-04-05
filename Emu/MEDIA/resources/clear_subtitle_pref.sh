#!/bin/sh
# Clears the saved subtitle language preference from gvu.conf.
# Run this from DinguxCommander to make GVU ask for your language again
# on the next subtitle search.

CONF="$(dirname "$0")/../gvu.conf"

if [ ! -f "$CONF" ]; then
    echo "ERROR: gvu.conf not found at $CONF"
    exit 1
fi

# Remove the sub_lang line (POSIX sed -i workaround for BusyBox)
TMP="$(mktemp)"
grep -v '^sub_lang[[:space:]]*=' "$CONF" > "$TMP"
mv "$TMP" "$CONF"

echo "Subtitle language preference cleared."
echo "GVU will ask for your preferred language on the next subtitle search."
