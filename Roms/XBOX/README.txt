Xbox games for hakuX

Supported files: .iso, .xiso, .chd and .sqfs

The SD card is FAT32, which cannot hold a file bigger than 4 GB. Many Xbox
games are bigger than that, so they need one or both of the steps below.
Do them on a computer, then copy the result to this folder.


1. Trim the image with extract-xiso

A full disc dump is about 7.3 GB no matter the game. Most of that is a video
partition and padding the game never reads. extract-xiso rewrites the image
with only the game's files:

    extract-xiso -r "Game.iso"

This rewrites Game.iso in place and keeps the original as Game.iso.old.
Most games come out well under 4 GB. If yours does, you are done.

extract-xiso: https://github.com/XboxDev/extract-xiso


2. Compress a large game to .chd

Some games are still over 4 GB after trimming (Halo 2 is 4.7 GB, and 3.1 GB
as a CHD). Convert the ISO with chdman, the same tool used for PlayStation
and Dreamcast games:

    chdman createdvd -i "Game.iso" -o "Game.chd"

Use createdvd, not createcd. chdman comes with MAME (mame-tools on Linux).


A .sqfs file holding one ISO also works on devices whose kernel can mount
SquashFS (make it with: mksquashfs "Game.iso" "Game.sqfs" -comp gzip).

The first launch of any game takes a minute or two with a black screen while
the emulated hard disk is set up. Use your own dumps of discs you own.
