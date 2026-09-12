#!/bin/sh
# Standalone launcher for BigPEmu (closed-source Atari Jaguar emulator) on
# spruceOS. Invoked with the ROM path as $1. Lives inside the bundled bigpemu
# directory on the card (alongside the binary and gl4es libGL).
#
# BigPEmu wants desktop OpenGL; every spruce GPU is GLES-only, so gl4es
# (bundled here as libGL.so.1 / libOpenGL.so) translates GL -> GLES. It is
# LD_PRELOADed the same way dArkMoss's proven launcher does it.

BIGPEMU_DIR="$(cd "$(dirname "$0")" && pwd)"
ROM="$1"

# Keep config + saves on the card, not in a volatile HOME. BigPEmu reads its
# userdata from $HOME/.bigpemu_userdata.
export HOME="/mnt/SDCARD/Saves/spruce/bigpemu"
USERDATA="$HOME/.bigpemu_userdata"
mkdir -p "$USERDATA"
[ -f "$USERDATA/BigPEmuConfig.bigpcfg" ] || \
    cp "$BIGPEMU_DIR/defaultconfigs/BigPEmuConfig.bigpcfg" "$USERDATA/BigPEmuConfig.bigpcfg" 2>/dev/null

# gl4es provides libGL; LD_PRELOAD it over the app's desktop-GL lookup.
export LD_LIBRARY_PATH="$BIGPEMU_DIR:$LD_LIBRARY_PATH"

cd "$BIGPEMU_DIR"
LD_PRELOAD=./libOpenGL.so ./bigpemu "$ROM"
