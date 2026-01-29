#!/bin/sh

fbgrab -a "/tmp/screenshot.png" 2>/dev/null 
rm "$1"
ffmpeg -i "/tmp/screenshot.png" -vf "rotate=PI" "$1"
