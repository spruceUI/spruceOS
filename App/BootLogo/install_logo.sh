#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

export PATH=/tmp/bin:$PATH
export LD_LIBRARY_PATH=/tmp/lib:$LD_LIBRARY_PATH

IMAGE_PATH="/mnt/SDCARD/spruce/imgs/image.png"
ERROR_IMAGE_PATH="/mnt/SDCARD/spruce/imgs/notfound.png"
LOGO_NAME="bootlogo"
PROCESSED_NAME="bootlogo_processed.bmp"
TEMP_BMP="/mnt/SDCARD/App/BootLogo/temp_logo.bmp"
MAX_SIZE=62234
DIR="$(dirname "$0")"
cd "$DIR" || exit 1

display_logo() {
    display -i "$DIR/$1.png" -d 3
}

log_message "--Debug-- PATH = $PATH"
log_message "--Debug-- LD_LIBRARY_PATH = $LD_LIBRARY_PATH"
log_message "--Debug-- DISPLAY_WIDTH = $DISPLAY_WIDTH"
log_message "--Debug-- DISPLAY_HEIGHT = $DISPLAY_HEIGHT"
log_message "--Debug-- LOGO_NAME = $LOGO_NAME"

# Check for input image in BMP or PNG format
LOGO_PATH="/mnt/SDCARD/App/BootLogo/$LOGO_NAME"
if [ -f "${LOGO_PATH}.bmp" ]; then
    LOGO_PATH="${LOGO_PATH}.bmp"
elif [ -f "${LOGO_PATH}.png" ]; then
    LOGO_PATH="${LOGO_PATH}.png"
else
    log_message "Error: Neither $LOGO_NAME.bmp nor $LOGO_NAME.png exist in the directory: $DIR"
    display --icon "$ERROR_IMAGE_PATH" -t "Boot logo not found. Cancelling boot logo swap." -d 1
    exit 1
fi

log_message "--Debug-- LOGO_PATH = $LOGO_PATH"

# Anbernic sizes its output from the bootlogo already on the device rather than
# from the panel, so it needs the artwork untouched. Keep a reference before the
# generic conversion below rewrites LOGO_PATH.
ORIG_LOGO_PATH="$LOGO_PATH"

# Convert image to BMP if not already.
#
# Skipped on Anbernic for two reasons: DISPLAY_WIDTH/HEIGHT is the wrong target
# there (a stock CubeXX has a 720x720 panel but a 640x480 bootlogo.bmp), and the
# ffprobe below is a 32-bit binary that cannot run under BaseOS.
case "$PLATFORM" in
    Anbernic*) SKIP_GENERIC_CONVERT=1 ;;
    *)         SKIP_GENERIC_CONVERT=0 ;;
esac

if [ "$SKIP_GENERIC_CONVERT" = "0" ]; then
    EXTENSION="${LOGO_PATH##*.}"
    BOOTLOGO_IMAGE_INFO="$(/mnt/SDCARD/spruce/bin/ffprobe -v error -select_streams v:0 -show_entries stream=width,height,pix_fmt -of compact=p=0:nk=1 -i "$LOGO_PATH")"
    if [ "$EXTENSION" != "bmp" ] || [ "$BOOTLOGO_IMAGE_INFO" != "$DISPLAY_WIDTH|$DISPLAY_HEIGHT|bgr24" ]; then
        log_message "Converting image to BMP format with resolution ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}..."
        ffmpeg -y -i "$LOGO_PATH" -vf "scale='if(gt(iw/ih,$DISPLAY_WIDTH/$DISPLAY_HEIGHT),$DISPLAY_WIDTH,-1)':'if(gt(iw/ih,$DISPLAY_WIDTH/$DISPLAY_HEIGHT),-1,$DISPLAY_HEIGHT)',pad=$DISPLAY_WIDTH:$DISPLAY_HEIGHT:($DISPLAY_WIDTH-iw)/2:($DISPLAY_HEIGHT-ih)/2:black" -pix_fmt bgr24 "$TEMP_BMP" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            log_message "Error: Unable to convert image to BMP format. Ensure FFmpeg is installed and the image path is correct."
            display --icon "$ERROR_IMAGE_PATH" -t "Cannot convert image. Cancelling boot logo swap." -d 1
            exit 1
        fi
        LOGO_PATH="$TEMP_BMP"
    fi
fi

log_message "--Debug-- new LOGO_PATH = $LOGO_PATH"

# Read a little-endian uint32 out of a file. Used to pull width and height from
# a BMP header (offsets 18 and 22) with only busybox dd and od.
read_le32() {
    _f="$1"; _off="$2"
    _bytes="$(dd if="$_f" bs=1 skip="$_off" count=4 2>/dev/null | od -An -tu1)"
    [ -n "$_bytes" ] || { echo ""; return 1; }
    # shellcheck disable=SC2086
    set -- $_bytes
    [ "$#" -eq 4 ] || { echo ""; return 1; }
    _v=$(( $1 + $2 * 256 + $3 * 65536 + $4 * 16777216 ))
    # BMP height is signed; a negative value means the rows are stored top-down.
    [ "$_v" -gt 2147483647 ] && _v=$(( 4294967296 - _v ))
    echo "$_v"
}

case "$PLATFORM" in
    A30)
        # Image conversion: rotation, resizing, compression
        log_message "Processing image..."
        ffmpeg -i "$LOGO_PATH" -vf "transpose=2" -pix_fmt bgra "$PROCESSED_NAME" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            log_message "Error: Unable to process image with FFmpeg."
            display --icon "$ERROR_IMAGE_PATH" -t "Cannot convert image. Cancelling boot logo swap." -d 1
            rm -f "$TEMP_BMP" "$PROCESSED_NAME"
            exit 1
        fi

        # Compress image
        gzip -k "$PROCESSED_NAME"
        PROCESSED_PATH="$PROCESSED_NAME.gz"
        LOGO_SIZE=$(wc -c < "$PROCESSED_PATH")

        # Check dimensions of compressed image
        if [ "$LOGO_SIZE" -gt "$MAX_SIZE" ]; then
            log_message "Error: Compressed file is larger than 62 KB ($LOGO_SIZE bytes)."
            display --icon "$ERROR_IMAGE_PATH" -t "Image is too large. Cancelling boot logo swap." -d 1
            rm "$PROCESSED_PATH" boot0 boot0-suffix
            rm -f "$TEMP_BMP" "$PROCESSED_NAME"
            exit 1
        fi

        # Backup partition
        log_message "Creating backup of original partition..."
        cp /dev/mtdblock0 boot0
        if [ $? -ne 0 ]; then
            log_message "Error: Unable to create a backup of the partition."
            display --icon "$ERROR_IMAGE_PATH" -t "Couldn't back up boot partition. Cancelling boot logo swap." -d 1
            rm -f "$TEMP_BMP" "$PROCESSED_NAME"
            exit 1
        fi

        # Recover offset from firmware version
        VERSION=$(cat /usr/miyoo/version)
        OFFSET_PATH="res/offset-$VERSION"
        if [ ! -f "$OFFSET_PATH" ]; then
            log_message "Error: Offset not found for firmware version ($VERSION)."
            display --icon "$ERROR_IMAGE_PATH" -t "Firmware is not compatible. Cancelling boot logo swap." -d 1
            rm -f "$TEMP_BMP" "$PROCESSED_NAME"
            rm "$PROCESSED_PATH" boot0
            exit 1
        fi
        OFFSET=$(cat "$OFFSET_PATH")

        # Display update image
        log_message "Displaying update image..."
        display --icon "$IMAGE_PATH" -t "Updating boot logo, please wait..."

        # Update bootlogo in memory
        log_message "Updating BootLogo..."
        OFFSET_PART=$((OFFSET + LOGO_SIZE))
        dd if=boot0 of=boot0-suffix bs=1 skip=$OFFSET_PART > /dev/null 2>&1
        dd if="$PROCESSED_PATH" of=boot0 bs=1 seek=$OFFSET > /dev/null 2>&1
        dd if=boot0-suffix of=boot0 bs=1 seek=$OFFSET_PART > /dev/null 2>&1

        log_message "Writing updated partition..."
        mtd write "$DIR/boot0" boot > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            log_message "Error: Unable to write updated partition."
            display --icon "$ERROR_IMAGE_PATH" -t "Couldn't write updated partition. Cancelling boot logo swap." -d 1
            rm "$PROCESSED_PATH" "$PROCESSED_NAME" "$TEMP_BMP" boot0 boot0-suffix
            exit 1
        fi

        rm -f "$PROCESSED_PATH" "$PROCESSED_NAME" "$TEMP_BMP" boot0 boot0-suffix
        ;;
    "Flip")

        display --icon "$IMAGE_PATH" -t "Updating boot logo, please wait..."

        # Setting up environment
        log_message "Preparing system..."
        DIR="$(cd "$(dirname "$0")" && pwd)"
        cd "$DIR" || exit 1
        cp -r payload/* /tmp
        if [ $? -ne 0 ]; then
            log_message "Error: Unable to write to disk."
            display --icon "$ERROR_IMAGE_PATH" -t "Couldn't create needed folders. Cancelling boot logo swap." -d 1
            rm -f "$TEMP_BMP"
            exit 1
        fi        
        cd /tmp

        # Extracting Boot Image
        log_message "Extracting Boot files..."
        dd if=/dev/mtd2ro of=boot.img bs=131072

        # Unpacking Boot Image
        log_message "Unpacking Boot files..."
        mkdir -p bootimg
        unpackbootimg -i boot.img -o bootimg

        # Unpacking Resources
        log_message "Unpacking Boot resources..."
        mkdir -p bootres
        if [ $? -ne 0 ]; then
            log_message "Error: Unable to write to disk."
            display --icon "$ERROR_IMAGE_PATH" -t "Couldn't create needed folders. Cancelling boot logo swap." -d 1
            rm -f "$TEMP_BMP"
            exit 1
        fi
        cp bootimg/boot.img-second bootres/
        cd bootres
        rsce_tool -u boot.img-second

        # Replacing logo
        log_message "Replacing Boot logo..."
        cp -f "$LOGO_PATH" ./logo.bmp
        cp -f "$LOGO_PATH" ./logo_kernel.bmp

        # Packing Resources
        log_message "Packing updated Boot resources..."
        for file in *; do
            [ "$(basename "$file")" != "boot.img-second" ] && set -- "$@" -p "$file"
        done
        rsce_tool "$@"

        # Packing Boot Image
        log_message "Packing updated Boot files..."
        cp -f boot-second ../bootimg
        cd ../
        rm boot.img
        mkbootimg --kernel bootimg/boot.img-kernel --second bootimg/boot-second --base 0x10000000 --kernel_offset 0x00008000 --ramdisk_offset 0xf0000000 --second_offset 0x00f00000 --pagesize 2048 --hashtype sha1 -o boot.img
        if [ $? -ne 0 ]; then
            log_message "Error: Unable to create new boot image."
            display --icon "$ERROR_IMAGE_PATH" -t "Couldn't pack new boot image. Cancelling boot logo swap." -d 1
            rm -f "$TEMP_BMP"
            exit 1
        fi

        # Flash new Boot Image
        log_message "Flashing updated Boot files..."
        flashcp boot.img /dev/mtd2 && sync

        # Clean up
        log_message "Cleaning temporal files..."
        cd ../
        rm -rf /tmp/bootimg /tmp/bootres /tmp/payload /tmp/boot.img 2>/dev/null
        rm -f "$TEMP_BMP"
        ;;
    "Brick" | "BrickPro" | "SmartPro" | "SmartProS")
        # A much faster and more simple implementation than Miyoo's devices
        # TrimUI devices are much more lenient with regards to bootlogo size, mostly as a result of the larger eMMC flash (8GB vs 16MB for A30 and 128MB for Flip)
        if [ $(wc -c < "$LOGO_PATH") -ge $((6 * 1024 * 1024)) ]; then
            display --icon "$ERROR_IMAGE_PATH" -t "Image is too large, must be less than 6MB. 
            Cancelling boot logo swap." -d 1
            rm -f "$TEMP_BMP"
            exit 1
        fi

        display --icon "$IMAGE_PATH" -t "Updating boot logo, please wait..."
        BOOT_PATH="/mnt/boot"
        [ ! -d $BOOT_PATH ] && mkdir $BOOT_PATH
        mount -t vfat /dev/mmcblk0p1 $BOOT_PATH
        if ! cp $LOGO_PATH $BOOT_PATH/bootlogo.bmp; then
            display --icon "$ERROR_IMAGE_PATH" -t "Couldn't write boot logo. Cancelling boot logo swap." -d 1
            umount "$BOOT_PATH" 2>/dev/null
            rm -f "$TEMP_BMP" "$BOOT_PATH"
            exit 1
        fi
        sync
        umount $BOOT_PATH
        rm -rf "$TEMP_BMP" "$BOOT_PATH"
        ;;
    "Anbernic"*)
        # Anbernic H700 (the RG XX line), on stock firmware and on BaseOS alike.
        # Boot0/U-Boot draws bootlogo.bmp from the boot-resource partition (p2,
        # vfat) on TF1. Replacing it needs no runtime setting or flashing.
        #
        # p2 is also where U-Boot reads its DTBs from, and it has no A/B
        # protection, so a botched write here costs the boot rather than the
        # picture. BaseOS's own docs decline to touch p2 at runtime for exactly
        # that reason, and use dd conv=notrunc when they do. Three rules keep
        # this inside the safe regime:
        #
        #   1. only ever overwrite an EXISTING bootlogo.bmp, never create one -
        #      creating a file is what allocates clusters and rewrites the FAT
        #   2. match its byte count exactly, and refuse the write otherwise
        #   3. dd conv=notrunc, so the bytes change in place and the file's
        #      cluster chain is never touched
        #
        # Dimensions come from the bootlogo already on the device, not from a
        # table: the vendor's geometry is not predictable from the panel. A
        # stock CubeXX has a 720x720 screen and a 640x480 bootlogo, while BaseOS
        # writes 720x720 on the same hardware. Reading the file is right on both.
        BOOT_DEV="/dev/mmcblk0p2"
        BOOT_PATH="/tmp/bootres"
        BACKUP="/mnt/SDCARD/App/BootLogo/bootlogo-backup.bmp"

        if [ ! -b "$BOOT_DEV" ]; then
            log_message "Error: $BOOT_DEV not present."
            display --icon "$ERROR_IMAGE_PATH" -t "Boot partition not found. Cancelling boot logo swap." -d 1
            rm -f "$TEMP_BMP"
            exit 1
        fi

        display --icon "$IMAGE_PATH" -t "Updating boot logo, please wait..."

        mkdir -p "$BOOT_PATH"
        if ! mount -t vfat "$BOOT_DEV" "$BOOT_PATH" 2>/dev/null; then
            log_message "Error: could not mount $BOOT_DEV."
            display --icon "$ERROR_IMAGE_PATH" -t "Couldn't open boot partition. Cancelling boot logo swap." -d 1
            rmdir "$BOOT_PATH" 2>/dev/null
            rm -f "$TEMP_BMP"
            exit 1
        fi

        TARGET_BMP="$BOOT_PATH/bootlogo.bmp"
        if [ ! -f "$TARGET_BMP" ]; then
            # Rule 1. Without an existing file there is no known-good geometry
            # and no way to write without allocating - so decline entirely.
            log_message "Error: no existing bootlogo.bmp on $BOOT_DEV; refusing to create one."
            display --icon "$ERROR_IMAGE_PATH" -t "No boot logo to replace. Cancelling boot logo swap." -d 1
            umount "$BOOT_PATH" 2>/dev/null; rmdir "$BOOT_PATH" 2>/dev/null
            rm -f "$TEMP_BMP"
            exit 1
        fi

        TARGET_SIZE="$(wc -c < "$TARGET_BMP")"
        BL_W="$(read_le32 "$TARGET_BMP" 18)"
        BL_H="$(read_le32 "$TARGET_BMP" 22)"
        log_message "--Debug-- existing bootlogo: ${BL_W}x${BL_H}, $TARGET_SIZE bytes"

        if [ -z "$BL_W" ] || [ -z "$BL_H" ] || [ "$BL_W" -le 0 ] || [ "$BL_H" -le 0 ]; then
            log_message "Error: could not read dimensions from the existing bootlogo."
            display --icon "$ERROR_IMAGE_PATH" -t "Boot logo unreadable. Cancelling boot logo swap." -d 1
            umount "$BOOT_PATH" 2>/dev/null; rmdir "$BOOT_PATH" 2>/dev/null
            rm -f "$TEMP_BMP"
            exit 1
        fi

        # The RG28XX's panel is mounted turned 90 degrees counter-clockwise, and
        # the BMP has to hold the pixels the panel scans out - the same
        # convention as the vendor's own logo. So the artwork is composed at the
        # pre-rotation size and turned last. Two independent sources agree on
        # the angle: BaseOS devices.json gives panel_rotation_ccw 90 for rg28xx
        # and 0 for every other target, and spruce's own AnbernicRG28XX.cfg sets
        # DISPLAY_ROTATION 270. transpose=2 is ffmpeg's 90 counter-clockwise.
        case "$PLATFORM" in
            AnbernicRG28XX) ROT_VF=",transpose=2"; TW="$BL_H"; TH="$BL_W" ;;
            *)              ROT_VF="";            TW="$BL_W"; TH="$BL_H" ;;
        esac
        log_message "--Debug-- composing at ${TW}x${TH}, rotation '${ROT_VF:-none}'"

        # Fit the artwork inside the frame and letterbox the remainder, so odd
        # aspect ratios are never stretched.
        if ! ffmpeg -y -i "$ORIG_LOGO_PATH" -vf "scale='if(gt(iw/ih,$TW/$TH),$TW,-1)':'if(gt(iw/ih,$TW/$TH),-1,$TH)',pad=$TW:$TH:($TW-iw)/2:($TH-ih)/2:black${ROT_VF}" -pix_fmt bgr24 "$TEMP_BMP" > /dev/null 2>&1; then
            log_message "Error: could not convert the image to ${BL_W}x${BL_H} BMP."
            display --icon "$ERROR_IMAGE_PATH" -t "Cannot convert image. Cancelling boot logo swap." -d 1
            umount "$BOOT_PATH" 2>/dev/null; rmdir "$BOOT_PATH" 2>/dev/null
            rm -f "$TEMP_BMP"
            exit 1
        fi

        # Rule 2. This is the load-bearing check: an identical byte count is
        # what lets the write stay inside the existing clusters. Anything else
        # would extend or truncate the file and rewrite the allocation table.
        NEW_SIZE="$(wc -c < "$TEMP_BMP")"
        if [ "$NEW_SIZE" != "$TARGET_SIZE" ]; then
            log_message "Error: converted logo is $NEW_SIZE bytes, expected $TARGET_SIZE. Refusing to write."
            display --icon "$ERROR_IMAGE_PATH" -t "Converted logo is the wrong size. Cancelling boot logo swap." -d 1
            umount "$BOOT_PATH" 2>/dev/null; rmdir "$BOOT_PATH" 2>/dev/null
            rm -f "$TEMP_BMP"
            exit 1
        fi

        # Keep the outgoing logo on the SD card so a bad choice is reversible
        # without reflashing. Only the first one, which is the factory logo.
        [ -f "$BACKUP" ] || cp "$TARGET_BMP" "$BACKUP" 2>/dev/null

        # Rule 3.
        log_message "Writing boot logo in place..."
        if ! dd if="$TEMP_BMP" of="$TARGET_BMP" conv=notrunc 2>/dev/null; then
            log_message "Error: could not write the boot logo."
            display --icon "$ERROR_IMAGE_PATH" -t "Couldn't write boot logo. Cancelling boot logo swap." -d 1
            umount "$BOOT_PATH" 2>/dev/null; rmdir "$BOOT_PATH" 2>/dev/null
            rm -f "$TEMP_BMP"
            exit 1
        fi

        sync
        umount "$BOOT_PATH" 2>/dev/null
        rmdir "$BOOT_PATH" 2>/dev/null
        rm -f "$TEMP_BMP"
        ;;
esac

# Clean up temporary files

log_message "Bootlogo updated successfully!"
display --icon "$IMAGE_PATH" -t "Boot logo updated successfully!" -d 1

# Visualizza immagine finale
display_logo "$LOGO_NAME"
