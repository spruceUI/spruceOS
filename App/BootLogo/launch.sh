#!/bin/sh

LOGO_NAME="bootlogo.bmp"

DIR="$(dirname "$0")"
cd "$DIR"

LOGO_PATH=$DIR/$LOGO_NAME
if [ ! -f $LOGO_PATH ]; then
    show "$DIR/res/missing.png" &
    sleep 2
    exit 1
fi

cp /dev/mtdblock0 boot0

VERSION=$(cat /usr/miyoo/version)
OFFSET_PATH="res/offset-$VERSION"

if [ ! -f "$OFFSET_PATH" ]; then
    show "$DIR/res/abort.png" &
    sleep 2
    exit 1
fi

# offset is found with binwalk mtdblock0
OFFSET=$(cat "$OFFSET_PATH")

IMAGE_PATH="$DIR/res/updating.png"
if [ ! -f "$IMAGE_PATH" ]; then
    echo "Image file not found at $IMAGE_PATH"
    exit 1
fi

show "$IMAGE_PATH" &

gzip -k "$LOGO_PATH"
LOGO_PATH=$LOGO_PATH.gz
LOGO_SIZE=$(wc -c < "$LOGO_PATH")

MAX_SIZE=62234
if [ "$LOGO_SIZE" -gt "$MAX_SIZE" ]; then
    show "$DIR/res/simplify.png" &
    sleep 2
    exit 1
fi

# workaround for missing conv=notrunc support
OFFSET_PART=$((OFFSET+LOGO_SIZE))
dd if=boot0 of=boot0-suffix bs=1 skip=$OFFSET_PART 2>/dev/null
dd if=$LOGO_PATH of=boot0 bs=1 seek=$OFFSET 2>/dev/null
dd if=boot0-suffix of=boot0 bs=1 seek=$OFFSET_PART 2>/dev/null

mtd write "$DIR/boot0" boot
killall -9 show

rm $LOGO_PATH boot0 boot0-suffix
mv $DIR $DIR.disabled

echo "DONE."
