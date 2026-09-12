#!/bin/sh
#
# Run ra64.universal on the RGB30 across every video driver it has, one at a
# time, each with its own log. Run by hand over SSH, never at boot.
#
# The question this exists to answer: does the shipped ra64.universal open a
# window on dArkMoss, and if not, at which call does it stop. One boot of the
# normal launch path gives one answer and overwrites its own log; this gives
# all of them side by side.
#
#   ssh spruce@<ip>   (or ark@<ip>, password ark)
#   sudo /mnt/SDCARD/spruce/scripts/platform/rgb30_ra_probe.sh
#
# Stops the frontend first, because two processes cannot both own the display,
# and puts it back on the way out even if a run dies or you Ctrl-C.
#
# If every driver fails identically and the logs blame the DRM device rather
# than the EGL config, that is SSH rather than the GPU: SDL's KMSDRM backend
# wants DRM master and a session started over ssh may not be able to take it.
# Re-run as
#
#   RA_PROBE_NO_MASTER=1 sudo -E .../rgb30_ra_probe.sh
#
# to set SDL_KMSDRM_REQUIRE_DRM_MASTER=0 and rule that out. Do not leave it on
# for the real answer - it changes what SDL is allowed to do.

set -u

if [ "${RA_PROBE_NO_MASTER:-0}" = "1" ]; then
    export SDL_KMSDRM_REQUIRE_DRM_MASTER=0
    echo "NOTE: SDL_KMSDRM_REQUIRE_DRM_MASTER=0 - diagnostic only"
fi

RA_DIR="/mnt/SDCARD/RetroArch"
RA_BIN="$RA_DIR/ra64.universal"
BASE_CFG="$RA_DIR/platform/retroarch-RGB30.cfg"
OUT="/mnt/SDCARD/Saves/spruce/ra_probe"
CORE="$RA_DIR/.retroarch/cores64/gambatte_libretro.so"

# Every video driver the binary actually carries. glcore and gl are separate
# code paths to the same GLES context; vulkan skips EGL entirely and is the one
# that would prove a config-only fix if it works. sdl2 is RA's SDL_Renderer
# path and is expected to fail - it is here as the control, because it is the
# one the original bug report captured.
DRIVERS="gl glcore vulkan sdl2"

restore() {
    echo
    echo "--- restarting the frontend"
    systemctl start spruce-launch.service 2>/dev/null
}
trap restore EXIT INT TERM

for f in "$RA_BIN" "$BASE_CFG" "$CORE"; do
    if [ ! -f "$f" ]; then
        echo "missing: $f" >&2
        exit 1
    fi
done

# Any ROM will do - it only has to get RetroArch as far as video init.
ROM=""
for d in /mnt/SDCARD/Roms/GBC /mnt/SDCARD/Roms/GB; do
    [ -d "$d" ] || continue
    ROM=$(find "$d" -maxdepth 1 -type f \( -name '*.gb' -o -name '*.gbc' -o -name '*.zip' \) 2>/dev/null | head -1)
    [ -n "$ROM" ] && break
done
if [ -z "$ROM" ]; then
    echo "no GB/GBC rom found to load - point ROM= at one by hand" >&2
    exit 1
fi

mkdir -p "$OUT"
echo "rom:  $ROM"
echo "out:  $OUT"

echo
echo "--- stopping the frontend"
systemctl stop spruce-launch.service 2>/dev/null
# The unit is KillMode=process, so give its children a moment to actually go.
i=0
while [ "$i" -lt 10 ]; do
    pgrep -f "MainUI|ra64.universal" >/dev/null 2>&1 || break
    i=$((i + 1))
    sleep 1
done

# Who holds the display now? If anything still does, every result below is
# about that and not about the driver.
echo "--- /dev/dri holders before we start:"
_found=0
for _fd in /proc/[0-9]*/fd/*; do
    _t="$(readlink "$_fd" 2>/dev/null)" || continue
    case "$_t" in /dev/dri/*)
        _p="${_fd#/proc/}"; _p="${_p%%/*}"
        echo "    pid $_p ($(tr '\0' ' ' < "/proc/$_p/cmdline" 2>/dev/null)) -> $_t"
        _found=1 ;;
    esac
done
[ "$_found" -eq 0 ] && echo "    (nobody)"

for drv in $DRIVERS; do
    cfg="$OUT/retroarch-$drv.cfg"
    log="$OUT/$drv.log"

    # Same config the real launch uses, with only video_driver changed, and
    # config_save_on_exit off so a failed run cannot rewrite the shipped file
    # and poison the next test.
    sed -e "s|^video_driver = .*|video_driver = \"$drv\"|" \
        -e "s|^config_save_on_exit = .*|config_save_on_exit = \"false\"|" \
        "$BASE_CFG" > "$cfg"

    echo
    echo "=============================================================="
    echo "video_driver = $drv"
    echo "=============================================================="

    # 20s is plenty to reach video init and well short of hanging the session.
    HOME="$RA_DIR/" \
    SDL_VIDEODRIVER=kmsdrm \
    timeout 20 "$RA_BIN" -v \
        --config "$cfg" \
        --log-file "$log" \
        -L "$CORE" "$ROM" >/dev/null 2>&1
    rc=$?

    if grep -q "Can't window GBM/EGL surfaces" "$log" 2>/dev/null; then
        verdict="FAILED - Can't window GBM/EGL surfaces"
    elif grep -qE "\[GL\] Version:|\[Vulkan\].*(device|Using)" "$log" 2>/dev/null; then
        verdict="OPENED A CONTEXT"
    elif [ "$rc" -eq 124 ]; then
        verdict="ran until the 20s timeout (that means it WORKED)"
    else
        verdict="exited rc=$rc - read the log"
    fi
    echo "  => $verdict"

    # The lines that say which call failed, rather than the whole log.
    grep -E "\[EGL\]|\[GL\] Version|\[GL\] Vendor|\[Vulkan\]|Can't |Could not |Failed |video_driver_init" \
        "$log" 2>/dev/null | tail -12 | sed 's/^/     /'
done

echo
echo "=============================================================="
echo "logs in $OUT - pull the whole directory off the card"
echo "the shipped retroarch-RGB30.cfg was never passed to RA, so it cannot"
echo "have been rewritten - every run used a copy under $OUT"
echo "=============================================================="
