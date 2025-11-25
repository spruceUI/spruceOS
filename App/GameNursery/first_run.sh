#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
[ "$PLATFORM" = "SmartPro" ] && BG_IMG="/mnt/SDCARD/spruce/imgs/bg_tree_wide.png" || BG_IMG="/mnt/SDCARD/spruce/imgs/bg_tree.png"

display --okay -i "$BG_IMG" -t "Welcome to the spruce Game Nursery! This is where we grow our curated collection of ports and free homebrew games for your enjoyment."
sleep 0.05
display --okay -i "$BG_IMG" -t "You can browse the games at your leisure; selections will be downloaded and installed automaticially."
sleep 0.05
display --okay -i "$BG_IMG" -t "Games that you have previously installed can also be easily reinstalled through this same interface, if needed."
sleep 0.05
display --okay -i "$BG_IMG" -t "The spruce team has the utmost respect for the developers of these games, and strives to comply with the respective license terms for each game in our collection."
sleep 0.05
display --okay -i "$BG_IMG" -t "We are happy to share some of our favorite ports and homebrew games with you, and hope you enjoy your Game Nursery experience. Happy gaming!"
sleep 0.05