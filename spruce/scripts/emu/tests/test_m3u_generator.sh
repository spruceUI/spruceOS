#!/bin/sh
set -eu

test_dir="$(mktemp -d /tmp/spruce-m3u.XXXXXX)"
trap 'find "$test_dir" -type f -exec rm -f -- {} +; find "$test_dir" -depth -type d -exec rmdir -- {} +' EXIT
sdcard="$test_dir/SDCARD"
script_dir="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

mkdir -p "$sdcard/spruce/scripts" "$sdcard/Roms"
cat > "$sdcard/spruce/scripts/helperFunctions.sh" <<'EOF'
start_pyui_message_writer() { :; }
display_image_and_text() { :; }
stop_pyui_message_writer() { :; }
auto_regen_tmp_update() { :; }
sync() { :; }
sleep() { :; }
EOF
sed "s@/mnt/SDCARD@$sdcard@g" "$script_dir/m3u_generator.sh" > "$test_dir/generator.sh"

run_case() {
    system="$1"
    extension="$2"
    disc="$3"
    roms="$sdcard/Roms/$system"
    mkdir -p "$roms"
    : > "$roms/Test Game ($disc 1).$extension"
    : > "$roms/Test Game ($disc 2).$extension"
    : > "$roms/Test Game ($disc 1).bad"
    : > "$roms/Unrelated ($disc 1).bad"
    : > "$roms/Cartridge.bin"

    sh "$test_dir/generator.sh" "/mnt/SDCARD/Emu/$system/../../Roms/$system/game"

    printf '.Test Game/Test Game (%s 1).%s\n.Test Game/Test Game (%s 2).%s\n' \
        "$disc" "$extension" "$disc" "$extension" | diff -u - "$roms/Test Game.m3u"
    while IFS= read -r entry; do
        test -f "$roms/$entry"
    done < "$roms/Test Game.m3u"
    test -f "$roms/.Test Game/Test Game ($disc 1).bad"
    test -f "$roms/Unrelated ($disc 1).bad"
    if [ "$system" = "MD" ] || [ "$system" = "ATARIST" ]; then
        test ! -e "$roms/Cartridge.cue"
    fi
}

run_case PS chd Disc
run_case DC cdi Disc
run_case AMIGA adf Disk
run_case ATARIST ST Disk
run_case CPC dsk Disk
run_case COMMODORE d64 Disk
run_case VIC20 d71 Disk
run_case X68000 d88 Disk
run_case DOS img Disk
run_case PCECD cue Disc
run_case MD iso Disc

roms="$sdcard/Roms/SEGACD"
mkdir -p "$roms"
for number in 1 2; do
    : > "$roms/CD Game (Disc $number).cue"
    : > "$roms/CD Game (Disc $number).bin"
done
sh "$test_dir/generator.sh" "/mnt/SDCARD/Emu/SEGACD/../../Roms/SEGACD/game"
printf '.CD Game/CD Game (Disc 1).cue\n.CD Game/CD Game (Disc 2).cue\n' |
    diff -u - "$roms/CD Game.m3u"
test -f "$roms/.CD Game/CD Game (Disc 1).bin"
test -f "$roms/.CD Game/CD Game (Disc 2).bin"

roms="$sdcard/Roms/MSX"
mkdir -p "$roms"
for number in 1 2; do
    : > "$roms/Revision (Disk $number) (Rev 1).dsk"
    : > "$roms/TOSEC (Disk $number of 2).dsk"
done
sh "$test_dir/generator.sh" "/mnt/SDCARD/Emu/MSX/../../Roms/MSX/game"
printf '.Revision (Rev 1)/Revision (Disk 1) (Rev 1).dsk\n.Revision (Rev 1)/Revision (Disk 2) (Rev 1).dsk\n' |
    diff -u - "$roms/Revision (Rev 1).m3u"
printf '.TOSEC/TOSEC (Disk 1 of 2).dsk\n.TOSEC/TOSEC (Disk 2 of 2).dsk\n' |
    diff -u - "$roms/TOSEC .m3u"

printf 'M3U generator tests passed.\n'
