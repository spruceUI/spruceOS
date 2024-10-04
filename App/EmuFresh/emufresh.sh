#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

IMAGE_PATH="/mnt/SDCARD/App/EmuFresh/refreshing.png"

if [ ! -f "$IMAGE_PATH" ]; then
    echo "Image file not found at $IMAGE_PATH"
    exit 1
fi

show_image "$IMAGE_PATH"

delete_gamelist_files() {
    rootdir="/mnt/SDCARD/roms"
    
    for system in "$rootdir"/*; do
        if [ -d "$system" ]; then
            # Exclude specific directories
            if echo "$system" | grep -qE "(.gamelists|PORTS|FBNEO|MAME2003PLUS|ARCADE|NEOGEO|CPS1|CPS2|CPS3|FFPLAY|EASYRPG|MSUMD|SCUMMVM|WOLF|QUAKE|DOOM)"; then
                continue
            fi
            # Find and delete miyoogamelist.xml files in non-excluded directories
            find "$system" -name "miyoogamelist.xml" -exec rm {} +
        fi
    done
}

delete_cache_files() {
    find /mnt/SDCARD/roms -name "*cache6.db" -exec rm {} \;
}

# Delete miyoogamelist.xml files first
delete_gamelist_files

# Then delete cache files
delete_cache_files

EMULATOR_BASE_PATH="/mnt/SDCARD/Emu/"
THEME_JSON_FILE="/config/system.json"

if [ ! -f "$THEME_JSON_FILE" ]; then
    exit 1
fi

THEME_PATH=$(awk -F'"' '/"theme":/ {print $4}' "$THEME_JSON_FILE")
THEME_PATH="${THEME_PATH%/}/"

if [ "${THEME_PATH: -1}" != "/" ]; then
    THEME_PATH="${THEME_PATH}/"
fi

DEFAULT_ICON_PATH="/mnt/SDCARD/icons/default/"
DEFAULT_ICON_SEL_PATH="${DEFAULT_ICON_PATH}sel/"

update_icons() {
    local CONFIG_FILE=$1

    OLD_ICON_PATH=$(awk -F'"' '/"icon":/ {print $4}' "$CONFIG_FILE")
    OLD_ICON_SEL_PATH=$(awk -F'"' '/"iconsel":/ {print $4}' "$CONFIG_FILE")

    ICON_FILE_NAME=$(basename "$OLD_ICON_PATH")
    ICON_SEL_FILE_NAME=$(basename "$OLD_ICON_SEL_PATH")

    THEME_ICON_PATH="${THEME_PATH}icons/${ICON_FILE_NAME}"
    THEME_ICON_SEL_PATH="${THEME_PATH}icons/sel/${ICON_SEL_FILE_NAME}"

    if [ -f "$THEME_ICON_PATH" ]; then
        NEW_ICON_PATH="$THEME_ICON_PATH"
    else
        NEW_ICON_PATH="${DEFAULT_ICON_PATH}${ICON_FILE_NAME}"
    fi

    if [ -f "$THEME_ICON_SEL_PATH" ]; then
        NEW_ICON_SEL_PATH="$THEME_ICON_SEL_PATH"
    else
        NEW_ICON_SEL_PATH="${DEFAULT_ICON_SEL_PATH}${ICON_SEL_FILE_NAME}"
    fi

    sed -i "s|${OLD_ICON_PATH}|${NEW_ICON_PATH}|g" "$CONFIG_FILE"
    sed -i "s|${OLD_ICON_SEL_PATH}|${NEW_ICON_SEL_PATH}|g" "$CONFIG_FILE"
}

find "$EMULATOR_BASE_PATH" -name "config.json" | while read CONFIG_FILE; do
    update_icons "$CONFIG_FILE"
done




# AMIGA Emulator paths and ROM extensions
AMIGA_EMU_PATH="/mnt/SDCARD/Emu/AMIGA"
AMIGA_ROMS_PATH="/mnt/SDCARD/Roms/AMIGA"
AMIGA_EXTENSIONS="*adf *adz *dms *fdi *ipf *hdf *hdz *lha *slave *info *cue *ccd *nrg *mds *iso *chd *uae *m3u *zip *7z *rp9"

# ARCADE Emulator paths and ROM extensions
ARCADE_EMU_PATH="/mnt/SDCARD/Emu/ARCADE"
ARCADE_ROMS_PATH="/mnt/SDCARD/Roms/ARCADE"
ARCADE_EXTENSIONS="*zip"

# ARDUBOY Emulator paths and ROM extensions
ARDUBOY_EMU_PATH="/mnt/SDCARD/Emu/ARDUBOY"
ARDUBOY_ROMS_PATH="/mnt/SDCARD/Roms/ARDUBOY"
ARDUBOY_EXTENSIONS="*elf *hex *arduboy *bin"

# ATARI Emulator paths and ROM extensions
ATARI_EMU_PATH="/mnt/SDCARD/Emu/ATARI"
ATARI_ROMS_PATH="/mnt/SDCARD/Roms/ATARI"
ATARI_EXTENSIONS="*a26 *bin *zip *7z"

# CHAI Emulator paths and ROM extensions
CHAI_EMU_PATH="/mnt/SDCARD/Emu/CHAI"
CHAI_ROMS_PATH="/mnt/SDCARD/Roms/CHAI"
CHAI_EXTENSIONS="*chailove"

# COLECO Emulator paths and ROM extensions
COLECO_EMU_PATH="/mnt/SDCARD/Emu/COLECO"
COLECO_ROMS_PATH="/mnt/SDCARD/Roms/COLECO"
COLECO_EXTENSIONS="*rom *ri *mx1 *mx2 *col *dsk *cas *sg *sc *m3u *zip *7z"

# COMMODORE Emulator paths and ROM extensions
COMMODORE_EMU_PATH="/mnt/SDCARD/Emu/COMMODORE"
COMMODORE_ROMS_PATH="/mnt/SDCARD/Roms/COMMODORE"
COMMODORE_EXTENSIONS="*d64 *zip *7z *t64 *crt *prg *nib *tap"

# CPC Emulator paths and ROM extensions
CPC_EMU_PATH="/mnt/SDCARD/Emu/CPC"
CPC_ROMS_PATH="/mnt/SDCARD/Roms/CPC"
CPC_EXTENSIONS="*sna *dsk *kcr *bin *zip *7z"

# CPS1 Emulator paths and ROM extensions
CPS1_EMU_PATH="/mnt/SDCARD/Emu/CPS1"
CPS1_ROMS_PATH="/mnt/SDCARD/Roms/CPS1"
CPS1_EXTENSIONS="*zip *7z *cue"

# CPS2 Emulator paths and ROM extensions
CPS2_EMU_PATH="/mnt/SDCARD/Emu/CPS2"
CPS2_ROMS_PATH="/mnt/SDCARD/Roms/CPS2"
CPS2_EXTENSIONS="*zip *7z *cue"

# CPS3 Emulator paths and ROM extensions
CPS3_EMU_PATH="/mnt/SDCARD/Emu/CPS3"
CPS3_ROMS_PATH="/mnt/SDCARD/Roms/CPS3"
CPS3_EXTENSIONS="*zip *7z *cue"

# DC Emulator paths and ROM extensions
DC_EMU_PATH="/mnt/SDCARD/Emu/DC"
DC_ROMS_PATH="/mnt/SDCARD/Roms/DC"
DC_EXTENSIONS="*cdi *gdi *cue *iso *chd"

# DOOM Emulator paths and ROM extensions
DOOM_EMU_PATH="/mnt/SDCARD/Emu/DOOM"
DOOM_ROMS_PATH="/mnt/SDCARD/Roms/DOOM"
DOOM_EXTENSIONS="*zip *wad *exe"

# DOS Emulator paths and ROM extensions
DOS_EMU_PATH="/mnt/SDCARD/Emu/DOS"
DOS_ROMS_PATH="/mnt/SDCARD/Roms/DOS"
DOS_EXTENSIONS="*zip *dosz *exe *com *bat *iso *ins *img *ima *vhd *jrc *tc *m3u *m3u8 *conf"

# EASYRPG Emulator paths and ROM extensions
EASYRPG_EMU_PATH="/mnt/SDCARD/Emu/EASYRPG"
EASYRPG_ROMS_PATH="/mnt/SDCARD/Roms/EASYRPG"
EASYRPG_EXTENSIONS="*zip *ldb *easyrpg"

# EIGHTHUNDRED Emulator paths and ROM extensions
EIGHTHUNDRED_EMU_PATH="/mnt/SDCARD/Emu/EIGHTHUNDRED"
EIGHTHUNDRED_ROMS_PATH="/mnt/SDCARD/Roms/EIGHTHUNDRED"
EIGHTHUNDRED_EXTENSIONS="*xfd *atr *cdm *cas *bin *a52 *zip *7z *atx *car *com *xex"

# FAIRCHILD Emulator paths and ROM extensions
FAIRCHILD_EMU_PATH="/mnt/SDCARD/Emu/FAIRCHILD"
FAIRCHILD_ROMS_PATH="/mnt/SDCARD/Roms/FAIRCHILD"
FAIRCHILD_EXTENSIONS="*bin *rom *chf *zip"

# FAKE08 Emulator paths and ROM extensions
FAKE08_EMU_PATH="/mnt/SDCARD/Emu/FAKE08"
FAKE08_ROMS_PATH="/mnt/SDCARD/Roms/FAKE08"
FAKE08_EXTENSIONS="*p8"

# FBNEO Emulator paths and ROM extensions
FBNEO_EMU_PATH="/mnt/SDCARD/Emu/FBNEO"
FBNEO_ROMS_PATH="/mnt/SDCARD/Roms/FBNEO"
FBNEO_EXTENSIONS="*zip"

# FC Emulator paths and ROM extensions
FC_EMU_PATH="/mnt/SDCARD/Emu/FC"
FC_ROMS_PATH="/mnt/SDCARD/Roms/FC"
FC_EXTENSIONS="*fds *nes *unif *unf *zip *7z"

# FDS Emulator paths and ROM extensions
FDS_EMU_PATH="/mnt/SDCARD/Emu/FDS"
FDS_ROMS_PATH="/mnt/SDCARD/Roms/FDS"
FDS_EXTENSIONS="*fds *nes *unif *unf *zip *7z"

# FFPLAY Emulator paths and ROM extensions
FFPLAY_EMU_PATH="/mnt/SDCARD/Emu/FFPLAY"
FFPLAY_ROMS_PATH="/mnt/SDCARD/Roms/FFPLAY"
FFPLAY_EXTENSIONS="*mp4 *mp3"

# FIFTYTWOHUNDRED Emulator paths and ROM extensions
FIFTYTWOHUNDRED_EMU_PATH="/mnt/SDCARD/Emu/FIFTYTWOHUNDRED"
FIFTYTWOHUNDRED_ROMS_PATH="/mnt/SDCARD/Roms/FIFTYTWOHUNDRED"
FIFTYTWOHUNDRED_EXTENSIONS="*a52 *zip *7z *bin"

# GB Emulator paths and ROM extensions
GB_EMU_PATH="/mnt/SDCARD/Emu/GB"
GB_ROMS_PATH="/mnt/SDCARD/Roms/GB"
GB_EXTENSIONS="*bin *dmg *gb *gbc *zip *7z"

# GBA Emulator paths and ROM extensions
GBA_EMU_PATH="/mnt/SDCARD/Emu/GBA"
GBA_ROMS_PATH="/mnt/SDCARD/Roms/GBA"
GBA_EXTENSIONS="*bin *gba *zip *7z"

# GBC Emulator paths and ROM extensions
GBC_EMU_PATH="/mnt/SDCARD/Emu/GBC"
GBC_ROMS_PATH="/mnt/SDCARD/Roms/GBC"
GBC_EXTENSIONS="*bin *dmg *gb *gbc *zip *7z"

# GG Emulator paths and ROM extensions
GG_EMU_PATH="/mnt/SDCARD/Emu/GG"
GG_ROMS_PATH="/mnt/SDCARD/Roms/GG"
GG_EXTENSIONS="*bin *gg *zip *7z"

# GW Emulator paths and ROM extensions
GW_EMU_PATH="/mnt/SDCARD/Emu/GW"
GW_ROMS_PATH="/mnt/SDCARD/Roms/GW"
GW_EXTENSIONS="*mgw *zip *7z"

# INTELLIVISION Emulator paths and ROM extensions
INTELLIVISION_EMU_PATH="/mnt/SDCARD/Emu/INTELLIVISION"
INTELLIVISION_ROMS_PATH="/mnt/SDCARD/Roms/INTELLIVISION"
INTELLIVISION_EXTENSIONS="*bin *int *zip *7z"

# LYNX Emulator paths and ROM extensions
LYNX_EMU_PATH="/mnt/SDCARD/Emu/LYNX"
LYNX_ROMS_PATH="/mnt/SDCARD/Roms/LYNX"
LYNX_EXTENSIONS="*lnx *zip"

# MAME2003PLUS Emulator paths and ROM extensions
MAME2003PLUS_EMU_PATH="/mnt/SDCARD/Emu/MAME2003PLUS"
MAME2003PLUS_ROMS_PATH="/mnt/SDCARD/Roms/MAME2003PLUS"
MAME2003PLUS_EXTENSIONS="*zip"

# MD Emulator paths and ROM extensions
MD_EMU_PATH="/mnt/SDCARD/Emu/MD"
MD_ROMS_PATH="/mnt/SDCARD/Roms/MD"
MD_EXTENSIONS="*gen *smd *md *32x *bin *iso *sms *68k *chd *zip *7z"

# MEGADUCK Emulator paths and ROM extensions
MEGADUCK_EMU_PATH="/mnt/SDCARD/Emu/MEGADUCK"
MEGADUCK_ROMS_PATH="/mnt/SDCARD/Roms/MEGADUCK"
MEGADUCK_EXTENSIONS="*bin *zip *7z"

# MS Emulator paths and ROM extensions
MS_EMU_PATH="/mnt/SDCARD/Emu/MS"
MS_ROMS_PATH="/mnt/SDCARD/Roms/MS"
MS_EXTENSIONS="*gen *smd *md *32x *bin *iso *sms *68k *chd *zip *7z"

# MSU1 Emulator paths and ROM extensions
MSU1_EMU_PATH="/mnt/SDCARD/Emu/MSU1"
MSU1_ROMS_PATH="/mnt/SDCARD/Roms/MSU1"
MSU1_EXTENSIONS="*sfc *smc *bml *xml *bs"

# MSUMD Emulator paths and ROM extensions
MSUMD_EMU_PATH="/mnt/SDCARD/Emu/MSUMD"
MSUMD_ROMS_PATH="/mnt/SDCARD/Roms/MSUMD"
MSUMD_EXTENSIONS="*gen *smd *md *32x *bin *iso *sms *68k *chd *zip *7z"

# MSX Emulator paths and ROM extensions
MSX_EMU_PATH="/mnt/SDCARD/Emu/MSX"
MSX_ROMS_PATH="/mnt/SDCARD/Roms/MSX"
MSX_EXTENSIONS="*rom *mx1 *mx2 *dsk *cas *zip *7z *m3u"

# N64 Emulator paths and ROM extensions
N64_EMU_PATH="/mnt/SDCARD/Emu/N64"
N64_ROMS_PATH="/mnt/SDCARD/Roms/N64"
N64_EXTENSIONS="*n64 *v64 *z64 *bin *usa *pal *jap *zip *7z"

# NDS Emulator paths and ROM extensions
NDS_EMU_PATH="/mnt/SDCARD/Emu/NDS"
NDS_ROMS_PATH="/mnt/SDCARD/Roms/NDS"
NDS_EXTENSIONS="*nds *zip *7z *rar"

# NEOCD Emulator paths and ROM extensions
NEOCD_EMU_PATH="/mnt/SDCARD/Emu/NEOCD"
NEOCD_ROMS_PATH="/mnt/SDCARD/Roms/NEOCD"
NEOCD_EXTENSIONS="*cue *chd *m3u"

# NEOGEO Emulator paths and ROM extensions
NEOGEO_EMU_PATH="/mnt/SDCARD/Emu/NEOGEO"
NEOGEO_ROMS_PATH="/mnt/SDCARD/Roms/NEOGEO"
NEOGEO_EXTENSIONS="*zip *7z"

# NGP Emulator paths and ROM extensions
NGP_EMU_PATH="/mnt/SDCARD/Emu/NGP"
NGP_ROMS_PATH="/mnt/SDCARD/Roms/NGP"
NGP_EXTENSIONS="*ngp *ngc *zip *7z"

# NGPC Emulator paths and ROM extensions
NGPC_EMU_PATH="/mnt/SDCARD/Emu/NGPC"
NGPC_ROMS_PATH="/mnt/SDCARD/Roms/NGPC"
NGPC_EXTENSIONS="*ngp *ngc *zip *7z"

# OPENBOR Emulator paths and ROM extensions
OPENBOR_EMU_PATH="/mnt/SDCARD/Emu/OPENBOR"
OPENBOR_ROMS_PATH="/mnt/SDCARD/Roms/OPENBOR"
OPENBOR_EXTENSIONS="*pak"

# ODYSSEY Emulator paths and ROM extensions
ODYSSEY_EMU_PATH="/mnt/SDCARD/Emu/ODYSSEY"
ODYSSEY_ROMS_PATH="/mnt/SDCARD/Roms/ODYSSEY"
ODYSSEY_EXTENSIONS="*bin *zip *7z"

# PCE Emulator paths and ROM extensions
PCE_EMU_PATH="/mnt/SDCARD/Emu/PCE"
PCE_ROMS_PATH="/mnt/SDCARD/Roms/PCE"
PCE_EXTENSIONS="*pce *ccd *iso *img *chd *cue *zip *7z"

# PCECD Emulator paths and ROM extensions
PCECD_EMU_PATH="/mnt/SDCARD/Emu/PCECD"
PCECD_ROMS_PATH="/mnt/SDCARD/Roms/PCECD"
PCECD_EXTENSIONS="*pce *ccd *iso *img *chd *cue *zip *7z"

# PICO8 Emulator paths and ROM extensions
PICO8_EMU_PATH="/mnt/SDCARD/Emu/PICO8"
PICO8_ROMS_PATH="/mnt/SDCARD/Roms/PICO8"
PICO8_EXTENSIONS="*p8 *png *p8.png"

# POKE Emulator paths and ROM extensions
POKE_EMU_PATH="/mnt/SDCARD/Emu/POKE"
POKE_ROMS_PATH="/mnt/SDCARD/Roms/POKE"
POKE_EXTENSIONS="*min *zip"

# PORTS Emulator paths and ROM extensions
PORTS_EMU_PATH="/mnt/SDCARD/Emu/PORTS"
PORTS_ROMS_PATH="/mnt/SDCARD/Roms/PORTS"
PORTS_EXTENSIONS="*zip *sh"

# PS Emulator paths and ROM extensions
PS_EMU_PATH="/mnt/SDCARD/Emu/PS"
PS_ROMS_PATH="/mnt/SDCARD/Roms/PS"
PS_EXTENSIONS="*bin *cue *img *mdf *pbp *PBP *toc *cbn *m3u *chd"

# PSP Emulator paths and ROM extensions
PSP_EMU_PATH="/mnt/SDCARD/Emu/PSP"
PSP_ROMS_PATH="/mnt/SDCARD/Roms/PSP"
PSP_EXTENSIONS="*iso *cso"

# QUAKE Emulator paths and ROM extensions
QUAKE_EMU_PATH="/mnt/SDCARD/Emu/QUAKE"
QUAKE_ROMS_PATH="/mnt/SDCARD/Roms/QUAKE"
QUAKE_EXTENSIONS="*fbl *pak"

# SATELLAVIEW Emulator paths and ROM extensions
SATELLAVIEW_EMU_PATH="/mnt/SDCARD/Emu/SATELLAVIEW"
SATELLAVIEW_ROMS_PATH="/mnt/SDCARD/Roms/SATELLAVIEW"
SATELLAVIEW_EXTENSIONS="*bs *sfc *smc *swc *fig *st *zip *7z"

# SCUMMVM Emulator paths and ROM extensions
SCUMMVM_EMU_PATH="/mnt/SDCARD/Emu/SCUMMVM"
SCUMMVM_ROMS_PATH="/mnt/SDCARD/Roms/SCUMMVM"
SCUMMVM_EXTENSIONS="*scummvm"

# SEGACD Emulator paths and ROM extensions
SEGACD_EMU_PATH="/mnt/SDCARD/Emu/SEGACD"
SEGACD_ROMS_PATH="/mnt/SDCARD/Roms/SEGACD"
SEGACD_EXTENSIONS="*gen *smd *md *32x *cue *iso *sms *68k *chd *m3u *zip *7z"

# SEGASGONE Emulator paths and ROM extensions
SEGASGONE_EMU_PATH="/mnt/SDCARD/Emu/SEGASGONE"
SEGASGONE_ROMS_PATH="/mnt/SDCARD/Roms/SEGASGONE"
SEGASGONE_EXTENSIONS="*sms *gg *sg *mv *bin *rom *zip *7z"

# SEVENTYEIGHTHUNDRED Emulator paths and ROM extensions
SEVENTYEIGHTHUNDRED_EMU_PATH="/mnt/SDCARD/Emu/SEVENTYEIGHTHUNDRED"
SEVENTYEIGHTHUNDRED_ROMS_PATH="/mnt/SDCARD/Roms/SEVENTYEIGHTHUNDRED"
SEVENTYEIGHTHUNDRED_EXTENSIONS="*a78 *zip"

# SFC Emulator paths and ROM extensions
SFC_EMU_PATH="/mnt/SDCARD/Emu/SFC"
SFC_ROMS_PATH="/mnt/SDCARD/Roms/SFC"
SFC_EXTENSIONS="*smc *fig *sfc *gd3 *gd7 *dx2 *bsx *bs *swc *st *zip *7z"

# SGB Emulator paths and ROM extensions
SGB_EMU_PATH="/mnt/SDCARD/Emu/SGB"
SGB_ROMS_PATH="/mnt/SDCARD/Roms/SGB"
SGB_EXTENSIONS="*bin *gb *gbc *gba *zip *7z"

# SGFX Emulator paths and ROM extensions
SGFX_EMU_PATH="/mnt/SDCARD/Emu/SGFX"
SGFX_ROMS_PATH="/mnt/SDCARD/Roms/SGFX"
SGFX_EXTENSIONS="*pce *sgx *cue *ccd *chd *zip *7z"

# SUFAMI Emulator paths and ROM extensions
SUFAMI_EMU_PATH="/mnt/SDCARD/Emu/SUFAMI"
SUFAMI_ROMS_PATH="/mnt/SDCARD/Roms/SUFAMI"
SUFAMI_EXTENSIONS="*smc *zip *7z"

# SUPERVISION Emulator paths and ROM extensions
SUPERVISION_EMU_PATH="/mnt/SDCARD/Emu/SUPERVISION"
SUPERVISION_ROMS_PATH="/mnt/SDCARD/Roms/SUPERVISION"
SUPERVISION_EXTENSIONS="*sv *bin *zip *7z"

# THIRTYTWOX Emulator paths and ROM extensions
THIRTYTWOX_EMU_PATH="/mnt/SDCARD/Emu/THIRTYTWOX"
THIRTYTWOX_ROMS_PATH="/mnt/SDCARD/Roms/THIRTYTWOX"
THIRTYTWOX_EXTENSIONS="*gen *smd *md *32x *bin *iso *sms *68k *chd *zip *7z"

# TIC Emulator paths and ROM extensions
TIC_EMU_PATH="/mnt/SDCARD/Emu/TIC"
TIC_ROMS_PATH="/mnt/SDCARD/Roms/TIC"
TIC_EXTENSIONS="*tic *fd *sap *k7 *m7 *rom *zip *7z"

# VB Emulator paths and ROM extensions
VB_EMU_PATH="/mnt/SDCARD/Emu/VB"
VB_ROMS_PATH="/mnt/SDCARD/Roms/VB"
VB_EXTENSIONS="*vb *vboy *zip *7z"

# VECTREX Emulator paths and ROM extensions
VECTREX_EMU_PATH="/mnt/SDCARD/Emu/VECTREX"
VECTREX_ROMS_PATH="/mnt/SDCARD/Roms/VECTREX"
VECTREX_EXTENSIONS="*vec *zip *7z"

# VIC20 Emulator paths and ROM extensions
VIC20_EMU_PATH="/mnt/SDCARD/Emu/VIC20"
VIC20_ROMS_PATH="/mnt/SDCARD/Roms/VIC20"
VIC20_EXTENSIONS="*d64 *d6z *d71 *d7z *d80 *d81 *d82 *d8z *g64 *g6z *g41 *g4z *x64 *x6z *nib *nbz *d2m *d4m *t64 *tap *tcrt *prg *p00 *crt *bin *cmd *m3u *vfl *vsf *zip *7z *gz *20 *40 *60 *a0 *b0 *rom"

# VIDEOPAC Emulator paths and ROM extensions
VIDEOPAC_EMU_PATH="/mnt/SDCARD/Emu/VIDEOPAC"
VIDEOPAC_ROMS_PATH="/mnt/SDCARD/Roms/VIDEOPAC"
VIDEOPAC_EXTENSIONS="*bin *zip *7z"

# WOLF Emulator paths and ROM extensions
WOLF_EMU_PATH="/mnt/SDCARD/Emu/WOLF"
WOLF_ROMS_PATH="/mnt/SDCARD/Roms/WOLF"
WOLF_EXTENSIONS="*ecwolf *exe"

# WS Emulator paths and ROM extensions
WS_EMU_PATH="/mnt/SDCARD/Emu/WS"
WS_ROMS_PATH="/mnt/SDCARD/Roms/WS"
WS_EXTENSIONS="*ws *wsc *pc2 *zip *7z"

# WSC Emulator paths and ROM extensions
WSC_EMU_PATH="/mnt/SDCARD/Emu/WSC"
WSC_ROMS_PATH="/mnt/SDCARD/Roms/WSC"
WSC_EXTENSIONS="*ws *wsc *pc2 *zip *7z"

# X68000 Emulator paths and ROM extensions
X68000_EMU_PATH="/mnt/SDCARD/Emu/X68000"
X68000_ROMS_PATH="/mnt/SDCARD/Roms/X68000"
X68000_EXTENSIONS="*dim *zip *img *d88 *88d *hdm *dup *2hd *xdf *hdf *cmd *m3u *7z"

# ZXS Emulator paths and ROM extensions
ZXS_EMU_PATH="/mnt/SDCARD/Emu/ZXS"
ZXS_ROMS_PATH="/mnt/SDCARD/Roms/ZXS"
ZXS_EXTENSIONS="*tzx *tap *z80 *rzx *scl *trd *zip *7z"


check_and_rename() {
  local EMU_PATH="$1"
  local ROMS_PATH="$2"
  local EXTENSIONS="$3"
  local emu_config_path="$EMU_PATH/config.json"
  local emu_config_hide_path="$EMU_PATH/config_hidden.json"

  if [ -d "$ROMS_PATH" ]; then
    # Find ROM files in the folder (including subfolders) with the specified extensions
    if find "$ROMS_PATH" -type f \( $(echo $EXTENSIONS | sed 's/ / -o -iname /g' | sed 's/^/-iname /') \) | grep -q .; then
      [ -f "$emu_config_hide_path" ] && mv "$emu_config_hide_path" "$emu_config_path"
    else
      [ -f "$emu_config_path" ] && mv "$emu_config_path" "$emu_config_hide_path"
    fi
  else
    [ -f "$emu_config_path" ] && mv "$emu_config_path" "$emu_config_hide_path"
  fi
}




check_and_rename "$AMIGA_EMU_PATH" "$AMIGA_ROMS_PATH" "$AMIGA_EXTENSIONS"
check_and_rename "$ARCADE_EMU_PATH" "$ARCADE_ROMS_PATH" "$ARCADE_EXTENSIONS"
check_and_rename "$ARDUBOY_EMU_PATH" "$ARDUBOY_ROMS_PATH" "$ARDUBOY_EXTENSIONS"
check_and_rename "$ATARI_EMU_PATH" "$ATARI_ROMS_PATH" "$ATARI_EXTENSIONS"
check_and_rename "$CHAI_EMU_PATH" "$CHAI_ROMS_PATH" "$CHAI_EXTENSIONS"
check_and_rename "$COLECO_EMU_PATH" "$COLECO_ROMS_PATH" "$COLECO_EXTENSIONS"
check_and_rename "$COMMODORE_EMU_PATH" "$COMMODORE_ROMS_PATH" "$COMMODORE_EXTENSIONS"
check_and_rename "$CPC_EMU_PATH" "$CPC_ROMS_PATH" "$CPC_EXTENSIONS"
check_and_rename "$CPS1_EMU_PATH" "$CPS1_ROMS_PATH" "$CPS1_EXTENSIONS"
check_and_rename "$CPS2_EMU_PATH" "$CPS2_ROMS_PATH" "$CPS2_EXTENSIONS"
check_and_rename "$CPS3_EMU_PATH" "$CPS3_ROMS_PATH" "$CPS3_EXTENSIONS"
check_and_rename "$DC_EMU_PATH" "$DC_ROMS_PATH" "$DC_EXTENSIONS"
check_and_rename "$DOOM_EMU_PATH" "$DOOM_ROMS_PATH" "$DOOM_EXTENSIONS"
check_and_rename "$DOS_EMU_PATH" "$DOS_ROMS_PATH" "$DOS_EXTENSIONS"
check_and_rename "$EASYRPG_EMU_PATH" "$EASYRPG_ROMS_PATH" "$EASYRPG_EXTENSIONS"
check_and_rename "$EIGHTHUNDRED_EMU_PATH" "$EIGHTHUNDRED_ROMS_PATH" "$EIGHTHUNDRED_EXTENSIONS"
check_and_rename "$FAIRCHILD_EMU_PATH" "$FAIRCHILD_ROMS_PATH" "$FAIRCHILD_EXTENSIONS"
check_and_rename "$FAKE08_EMU_PATH" "$FAKE08_ROMS_PATH" "$FAKE08_EXTENSIONS"
check_and_rename "$FBNEO_EMU_PATH" "$FBNEO_ROMS_PATH" "$FBNEO_EXTENSIONS"
check_and_rename "$FC_EMU_PATH" "$FC_ROMS_PATH" "$FC_EXTENSIONS"
check_and_rename "$FDS_EMU_PATH" "$FDS_ROMS_PATH" "$FDS_EXTENSIONS"
check_and_rename "$FFPLAY_EMU_PATH" "$FFPLAY_ROMS_PATH" "$FFPLAY_EXTENSIONS"
check_and_rename "$FIFTYTWOHUNDRED_EMU_PATH" "$FIFTYTWOHUNDRED_ROMS_PATH" "$FIFTYTWOHUNDRED_EXTENSIONS"
check_and_rename "$GB_EMU_PATH" "$GB_ROMS_PATH" "$GB_EXTENSIONS"
check_and_rename "$GBA_EMU_PATH" "$GBA_ROMS_PATH" "$GBA_EXTENSIONS"
check_and_rename "$GBC_EMU_PATH" "$GBC_ROMS_PATH" "$GBC_EXTENSIONS"
check_and_rename "$GG_EMU_PATH" "$GG_ROMS_PATH" "$GG_EXTENSIONS"
check_and_rename "$GW_EMU_PATH" "$GW_ROMS_PATH" "$GW_EXTENSIONS"
check_and_rename "$INTELLIVISION_EMU_PATH" "$INTELLIVISION_ROMS_PATH" "$INTELLIVISION_EXTENSIONS"
check_and_rename "$LYNX_EMU_PATH" "$LYNX_ROMS_PATH" "$LYNX_EXTENSIONS"
check_and_rename "$MAME2003PLUS_EMU_PATH" "$MAME2003PLUS_ROMS_PATH" "$MAME2003PLUS_EXTENSIONS"
check_and_rename "$MD_EMU_PATH" "$MD_ROMS_PATH" "$MD_EXTENSIONS"
check_and_rename "$MEGADUCK_EMU_PATH" "$MEGADUCK_ROMS_PATH" "$MEGADUCK_EXTENSIONS"
check_and_rename "$MS_EMU_PATH" "$MS_ROMS_PATH" "$MS_EXTENSIONS"
check_and_rename "$MSU1_EMU_PATH" "$MSU1_ROMS_PATH" "$MSU1_EXTENSIONS"
check_and_rename "$MSUMD_EMU_PATH" "$MSUMD_ROMS_PATH" "$MSUMD_EXTENSIONS"
check_and_rename "$MSX_EMU_PATH" "$MSX_ROMS_PATH" "$MSX_EXTENSIONS"
check_and_rename "$N64_EMU_PATH" "$N64_ROMS_PATH" "$N64_EXTENSIONS"
check_and_rename "$NDS_EMU_PATH" "$NDS_ROMS_PATH" "$NDS_EXTENSIONS"
check_and_rename "$NEOCD_EMU_PATH" "$NEOCD_ROMS_PATH" "$NEOCD_EXTENSIONS"
check_and_rename "$NEOGEO_EMU_PATH" "$NEOGEO_ROMS_PATH" "$NEOGEO_EXTENSIONS"
check_and_rename "$NGP_EMU_PATH" "$NGP_ROMS_PATH" "$NGP_EXTENSIONS"
check_and_rename "$NGPC_EMU_PATH" "$NGPC_ROMS_PATH" "$NGPC_EXTENSIONS"
check_and_rename "$OPENBOR_EMU_PATH" "$OPENBOR_ROMS_PATH" "$OPENBOR_EXTENSIONS"
check_and_rename "$ODYSSEY_EMU_PATH" "$ODYSSEY_ROMS_PATH" "$ODYSSEY_EXTENSIONS"
check_and_rename "$PCE_EMU_PATH" "$PCE_ROMS_PATH" "$PCE_EXTENSIONS"
check_and_rename "$PCECD_EMU_PATH" "$PCECD_ROMS_PATH" "$PCECD_EXTENSIONS"
check_and_rename "$PICO8_EMU_PATH" "$PICO8_ROMS_PATH" "$PICO8_EXTENSIONS"
check_and_rename "$POKE_EMU_PATH" "$POKE_ROMS_PATH" "$POKE_EXTENSIONS"
# check_and_rename "$PORTS_EMU_PATH" "$PORTS_ROMS_PATH" "$PORTS_EXTENSIONS"
check_and_rename "$PS_EMU_PATH" "$PS_ROMS_PATH" "$PS_EXTENSIONS"
check_and_rename "$PSP_EMU_PATH" "$PSP_ROMS_PATH" "$PSP_EXTENSIONS"
check_and_rename "$QUAKE_EMU_PATH" "$QUAKE_ROMS_PATH" "$QUAKE_EXTENSIONS"
check_and_rename "$SATELLAVIEW_EMU_PATH" "$SATELLAVIEW_ROMS_PATH" "$SATELLAVIEW_EXTENSIONS"
check_and_rename "$SCUMMVM_EMU_PATH" "$SCUMMVM_ROMS_PATH" "$SCUMMVM_EXTENSIONS"
check_and_rename "$SEGACD_EMU_PATH" "$SEGACD_ROMS_PATH" "$SEGACD_EXTENSIONS"
check_and_rename "$SEGASGONE_EMU_PATH" "$SEGASGONE_ROMS_PATH" "$SEGASGONE_EXTENSIONS"
check_and_rename "$SEVENTYEIGHTHUNDRED_EMU_PATH" "$SEVENTYEIGHTHUNDRED_ROMS_PATH" "$SEVENTYEIGHTHUNDRED_EXTENSIONS"
check_and_rename "$SFC_EMU_PATH" "$SFC_ROMS_PATH" "$SFC_EXTENSIONS"
check_and_rename "$SGB_EMU_PATH" "$SGB_ROMS_PATH" "$SGB_EXTENSIONS"
check_and_rename "$SGFX_EMU_PATH" "$SGFX_ROMS_PATH" "$SGFX_EXTENSIONS"
check_and_rename "$SUFAMI_EMU_PATH" "$SUFAMI_ROMS_PATH" "$SUFAMI_EXTENSIONS"
check_and_rename "$SUPERVISION_EMU_PATH" "$SUPERVISION_ROMS_PATH" "$SUPERVISION_EXTENSIONS"
check_and_rename "$THIRTYTWOX_EMU_PATH" "$THIRTYTWOX_ROMS_PATH" "$THIRTYTWOX_EXTENSIONS"
check_and_rename "$TIC_EMU_PATH" "$TIC_ROMS_PATH" "$TIC_EXTENSIONS"
check_and_rename "$VB_EMU_PATH" "$VB_ROMS_PATH" "$VB_EXTENSIONS"
check_and_rename "$VECTREX_EMU_PATH" "$VECTREX_ROMS_PATH" "$VECTREX_EXTENSIONS"
check_and_rename "$VIC20_EMU_PATH" "$VIC20_ROMS_PATH" "$VIC20_EXTENSIONS"
check_and_rename "$VIDEOPAC_EMU_PATH" "$VIDEOPAC_ROMS_PATH" "$VIDEOPAC_EXTENSIONS"
check_and_rename "$WOLF_EMU_PATH" "$WOLF_ROMS_PATH" "$WOLF_EXTENSIONS"
check_and_rename "$WS_EMU_PATH" "$WS_ROMS_PATH" "$WS_EXTENSIONS"
check_and_rename "$WSC_EMU_PATH" "$WSC_ROMS_PATH" "$WSC_EXTENSIONS"
check_and_rename "$X68000_EMU_PATH" "$X68000_ROMS_PATH" "$X68000_EXTENSIONS"
check_and_rename "$ZXS_EMU_PATH" "$ZXS_ROMS_PATH" "$ZXS_EXTENSIONS"


killall -9 show
