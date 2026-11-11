Xbox games for hakuX

Supported files: .iso, .xiso and .sqfs

The SD card is FAT32, which cannot hold a file bigger than 4 GB. Many Xbox
games are bigger than that, so they need one or both of the steps below.
Do both on a computer, then copy the result to this folder.


1. Trim the image with extract-xiso

A full disc dump is about 7.3 GB no matter the game. Most of that is a video
partition and padding the game never reads. extract-xiso rewrites the image
with only the game's files:

    extract-xiso -r "Game.iso"

This rewrites Game.iso in place and keeps the original as Game.iso.old.
Most games come out well under 4 GB. If yours does, you are done.

extract-xiso: https://github.com/XboxDev/extract-xiso


2. Pack a large game into a .sqfs

Some games are still over 4 GB after trimming (Halo 2 is 4.7 GB). Put the
ISO inside a compressed SquashFS file and copy that instead:

    mksquashfs "Game.iso" "Game.sqfs" -comp gzip

The .sqfs must hold exactly one ISO and must itself be under 4 GB. Use gzip,
not zstd: older device kernels cannot read zstd. mksquashfs is in the
squashfs-tools package on Linux and in WSL on Windows.


The first launch of any game takes a minute or two with a black screen while
the emulated hard disk is set up. Use your own dumps of discs you own.
