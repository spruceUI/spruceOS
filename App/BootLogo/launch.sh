#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

IMAGE_PATH="/mnt/SDCARD/spruce/imgs/image.png"
ERROR_IMAGE_PATH="/mnt/SDCARD/spruce/imgs/notfound.png"
LOGO_NAME="bootlogo"
PROCESSED_NAME="bootlogo_processed.bmp"
TEMP_BMP="temp_logo.bmp"
MAX_SIZE=62234
DIR="$(dirname "$0")"
cd "$DIR" || exit 1

display_logo() {
    display -i "$DIR/$1.png" -d 1
}

# Check for input image in BMP or PNG format
LOGO_PATH="/mnt/SDCARD/App/BootLogo/$LOGO_NAME"
if [ -f "${LOGO_PATH}.bmp" ]; then
    LOGO_PATH="${LOGO_PATH}.bmp"
elif [ -f "${LOGO_PATH}.png" ]; then
    LOGO_PATH="${LOGO_PATH}.png"
else
    echo "Error: Neither $LOGO_NAME.bmp nor $LOGO_NAME.png exist in the directory: $DIR"
    display --icon "$ERROR_IMAGE_PATH" -t "Boot logo not found. Cancelling boot logo swap." -d 1
    exit 1
fi

# Convert image to BMP if not already
EXTENSION="${LOGO_PATH##*.}"
if [ "$EXTENSION" != "bmp" ]; then
    echo "Converting image to BMP format..."
    ffmpeg -i "$LOGO_PATH" -vf "scale='if(gt(iw/ih,640/480),640,-1)':'if(gt(iw/ih,640/480),-1,480)',pad=640:480:(640-iw)/2:(480-ih)/2:black" -pix_fmt bgr24 "$TEMP_BMP" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Unable to convert image to BMP format. Ensure FFmpeg is installed and the image path is correct."
        display --icon "$ERROR_IMAGE_PATH" -t "Cannot convert image. Cancelling boot logo swap." -d 1
        exit 1
    fi
    LOGO_PATH="$TEMP_BMP"
fi

# Image conversion: rotation, resizing, compression
echo "Processing image..."
ffmpeg -i "$LOGO_PATH" -vf "transpose=2" -pix_fmt bgra "$PROCESSED_NAME" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Unable to process image with FFmpeg."
    display --icon "$ERROR_IMAGE_PATH" -t "Cannot convert image. Cancelling boot logo swap." -d 1
    exit 1
fi

# Compress image
gzip -k "$PROCESSED_NAME"
PROCESSED_PATH="$PROCESSED_NAME.gz"
LOGO_SIZE=$(wc -c < "$PROCESSED_PATH")

# Check dimensions of compressed image
if [ "$LOGO_SIZE" -gt "$MAX_SIZE" ]; then
    echo "Error: Compressed file is larger than 62 KB ($LOGO_SIZE bytes)."
    display --icon "$ERROR_IMAGE_PATH" -t "Image is too large. Cancelling boot logo swap." -d 1
    rm "$PROCESSED_PATH" boot0 boot0-suffix
    rm -f "$TEMP_BMP" "$PROCESSED_NAME"
    exit 1
fi

# Backup partition
echo "Creating backup of original partition..."
cp /dev/mtdblock0 boot0
if [ $? -ne 0 ]; then
    echo "Error: Unable to create a backup of the partition."
    exit 1
fi

# Recover offset from firmware version
VERSION=$(cat /usr/miyoo/version)
OFFSET_PATH="res/offset-$VERSION"
if [ ! -f "$OFFSET_PATH" ]; then
    echo "Error: Offset not found for firmware version ($VERSION)."
    display --icon "$ERROR_IMAGE_PATH" -t "Firmware is not compatible. Cancelling boot logo swap." -d 1
    rm "$PROCESSED_PATH" boot0
    exit 1
fi
OFFSET=$(cat "$OFFSET_PATH")

# Display update image
echo "Displaying update image..."
display --icon "$IMAGE_PATH" -t "Updating boot logo, please wait..."

# Update bootlogo in memory
echo "Updating BootLogo..."
OFFSET_PART=$((OFFSET + LOGO_SIZE))
dd if=boot0 of=boot0-suffix bs=1 skip=$OFFSET_PART > /dev/null 2>&1
dd if="$PROCESSED_PATH" of=boot0 bs=1 seek=$OFFSET > /dev/null 2>&1
dd if=boot0-suffix of=boot0 bs=1 seek=$OFFSET_PART > /dev/null 2>&1

echo "Writing updated partition..."
mtd write "$DIR/boot0" boot > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Unable to write updated partition."
    display --icon "$ERROR_IMAGE_PATH" -t "Couldn't write updated partition. Cancelling boot logo swap." -d 1
    rm "$PROCESSED_PATH" boot0 boot0-suffix
    exit 1
fi

# Clean up temporary files
rm "$PROCESSED_PATH" boot0 boot0-suffix
rm -f "$TEMP_BMP" "$PROCESSED_NAME"
echo "Bootlogo updated successfully!"
display --icon "$IMAGE_PATH" -t "Boot logo updated successfully!" -d 1

# Visualizza immagine finale
display_logo "$LOGO_NAME"