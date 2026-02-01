#!/bin/sh

# As of spruceV4.0.0, only specific files and folders get deleted during the update process.
# Manipulate the delete lists in this file to ensure only the desired files get wiped before
# the new versions get installed.

# Please note that with the current implementation, files in the delete list CANNOT include spaces.

delete_list_from_dir() {
    delete_list="$1"
    base_dir="$2"
    for file in $delete_list; do

        case "$file" in
            ""|"."|".."|"/") continue ;; # prevent deleting weird relative paths
        esac

        target="$base_dir/$file"

        case "$target" in
            "$base_dir"|"$base_dir/") continue ;; # prevent nuking whole folder or SDCARD
        esac

        if [ -e "$target" ]; then
            echo "Deleting $target"
            rm -rf "$target"
        fi
    done

    echo "Remaining files in $base_dir:"
    ls -Al "$base_dir" 2>/dev/null
}


# exclude BootLogo app in case someone wants to keep their own custom logos
# exclude fn_editor in case someone makes their own custom button/switch scripts
# exclude PortMaster app (can we do away with Persistent/ now?)
# exclude RandomGame to retain the list of last 5 random games played
APP_DIR="/mnt/SDCARD/App"
APP_DELETE_LIST="
-FirmwareUpdate-
-OTA
-Updater
Credits
FileManagement
GameNursery
MiyooGamelist
PixelReader
PyUI
RetroArch
spruceBackup
spruceRestore
ThemeGarden
USBStorageMode
"

# Delete all spruce-provided emu folders; users should use custom-named system folders if 
# they want any changes to persist. Any user data in these should have already been backed
# up earlier in the update process anyhow.
EMU_DIR="/mnt/SDCARD/Emu"
EMU_DELETE_LIST="
A30PORTS
AMIGA
ARCADE
ARDUBOY
ATARI
ATARIST
CHAI
COLECO
COMMODORE
CPC
CPS1
CPS2
CPS3
-CUSTOM-SYSTEM-
DC
DOOM
DOS
EASYRPG
EIGHTHUNDRED
.emu_setup
FAIRCHILD
FAKE08
FBNEO
FC
FDS
FIFTYTWOHUNDRED
GAMETANK
GB
GBA
GBC
GG
GW
INTELLIVISION
LYNX
MAME2003PLUS
MD
MEDIA
MEGADUCK
MS
MSU1
MSUMD
MSX
N64
NAOMI
NDS
NEOCD
NEOGEO
NGP
NGPC
ODYSSEY
OPENBOR
PC98
PCE
PCECD
PICO8
POKE
PORTS
PS
PSP
QUAKE
SATELLAVIEW
SATURN
SCUMMVM
SEGACD
SEGASGONE
SEVENTYEIGHTHUNDRED
SFC
SGB
SGFX
SUFAMI
SUPERVISION
THIRTYTWOX
TIC
VB
VECTREX
VIC20
VIDEOPAC
WOLF
WS
WSC
X68000
ZXS
"

# exclude bin, bin64, a30, brick, flip, miyoomini folders as we need those for pyui
SPRUCE_DIR="/mnt/SDCARD/spruce"
SPRUCE_DELETE_LIST="
archives
etc
FIRMWARE_UPDATE
flags
imgs
scripts
www
spruce
"

# exclude RetroArch folder in order to keep user-added assets from getting nuked.
SDCARD_PATH="/mnt/SDCARD"
SDCARD_DELETE_LIST="
.github
.tmp_update
Icons
miyoo
miyoo355
trimui
.gitattributes
.gitignore
autorun.inf
create_spruce_release.bat
create_spruce_release.sh
LICENSE
Pico8.Native.INFO.txt
README.md
"

################
##### MAIN #####
################

echo "----------------------"
echo "Beginning file cleanup"
echo "----------------------"

echo "SD card contents at beginning of cleanup:"
ls -Al /mnt/SDCARD

echo "-------------------"
echo "App folder deletion"
echo "-------------------"

delete_list_from_dir "$APP_DELETE_LIST" "$APP_DIR"

echo "-------------------"
echo "Emu folder deletion"
echo "-------------------"

delete_list_from_dir "$EMU_DELETE_LIST" "$EMU_DIR"

echo "----------------------"
echo "spruce folder deletion"
echo "----------------------"

delete_list_from_dir "$SPRUCE_DELETE_LIST" "$SPRUCE_DIR"

echo "---------------------"
echo "Misc. SD card cleanup"
echo "---------------------"

delete_list_from_dir "$SDCARD_DELETE_LIST" "$SDCARD_PATH"

echo "---------------------"
echo "File cleanup complete"
echo "---------------------"
