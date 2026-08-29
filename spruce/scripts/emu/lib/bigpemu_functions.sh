#!/bin/sh
# BigPEmu (standalone, closed-source Atari Jaguar emulator) launch handler.
# 64-bit devices only - there is no ARM32 BigPEmu build.
#
# BigPEmu wants desktop OpenGL and every spruce GPU is GLES-only, so gl4es
# (bundled as libGL.so.1 / libOpenGL.so) translates GL -> GLES and is
# LD_PRELOADed, matching dArkMoss's proven launcher. BigPEmu's config already
# carries keyboard bindings, so gptokeyb2 maps the pad to those keys rather
# than binding each device's controller GUID.

run_bigpemu_standalone() {
    BIGPEMU_DIR="$EMU_DIR/bigpemu"

    # BigPEmu is heavy; give it the full clock regardless of the Governor
    # setting (which is shared with the virtualjaguar core).
    set_performance

    # Config + saves on the card, seeded once from the shipped default.
    export HOME="/mnt/SDCARD/Saves/spruce/bigpemu"
    mkdir -p "$HOME/.bigpemu_userdata"
    [ -f "$HOME/.bigpemu_userdata/BigPEmuConfig.bigpcfg" ] || \
        cp "$BIGPEMU_DIR/defaultconfigs/BigPEmuConfig.bigpcfg" \
           "$HOME/.bigpemu_userdata/BigPEmuConfig.bigpcfg" 2>/dev/null

    /mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME" 2>/dev/null

    # Jaguar images load directly; only unpack archives.
    TEMP_ROM=""
    case "$ROM_FILE" in
        *.zip)
            TEMP_ROM=$(mktemp -d)
            "$(get_python_path)" -c "
import zipfile, sys
with zipfile.ZipFile(sys.argv[1]) as z: z.extractall(sys.argv[2])
" "$ROM_FILE" "$TEMP_ROM" 2>/dev/null
            ROM_PATH="$(find "$TEMP_ROM" -type f | head -1)"
            ;;
        *.7z)
            TEMP_ROM=$(mktemp -d)
            7zr e "$ROM_FILE" -o"$TEMP_ROM" >/dev/null 2>&1
            ROM_PATH="$(find "$TEMP_ROM" -type f | head -1)"
            ;;
        *)
            ROM_PATH="$ROM_FILE"
            ;;
    esac

    export LD_LIBRARY_PATH="$BIGPEMU_DIR:$LD_LIBRARY_PATH"
    cd "$BIGPEMU_DIR"

    # Pad -> keyboard bridge (BigPEmu reads its own keyboard bindings).
    if [ -x ./gptokeyb2 ]; then
        ./gptokeyb2 "bigpemu" -c "./bigpemu.gptk" &
        sleep 0.3
    fi

    log_message "bigpemu_functions.sh: launching $ROM_PATH"
    LD_PRELOAD=./libOpenGL.so ./bigpemu "$ROM_PATH" > "$(emu_log_file)" 2>&1

    kill -9 "$(pidof gptokeyb2)" 2>/dev/null
    [ -n "$TEMP_ROM" ] && rm -rf "$TEMP_ROM"
}
