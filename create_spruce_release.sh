#!/bin/bash

cd "$(dirname "$0")"

ARCHIVE_NAME="spruce"
VERSION_FILE="spruce/spruce"
VERSION=

if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: could not find file $VERSION_FILE"
    read
    exit 1
fi

VERSION=$(< "$VERSION_FILE")

if [ "$VERSION" == "" ]; then
    echo "Error: failed to retrieve version from $VERSION_FILE"
    read
    exit 1
fi

OUTPUT_7Z="${ARCHIVE_NAME}V${VERSION}.7z"

if [ -f "$OUTPUT_7Z" ]; then
    echo "Removing already existing $OUTPUT_7Z"
    rm "$OUTPUT_7Z"
fi

7z a -t7z -mx=9 -xr!.git* -x!.gitignore -x!.gitattributes -x!"$(basename "$0")" -x!create_spruce_release.bat "$OUTPUT_7Z" *

if [ $? -ne 0 ]; then
    echo "Error: failed to create 7z archive"
    read
    exit 1
fi

echo "7z archive $OUTPUT_7Z created successfully"
read
exit 0