#!/usr/bin/bash

echo "[Desktop Entry]
Type=Application
Name=BigPEmu
GenericName=Atari Jaguar Emulator
Exec=$PWD/bigpemu
Icon=$PWD/bigpemu-icon.png
Terminal=false
Categories=Game;Emulator;
Keywords=bigpemu;atari;jaguar;emulator;
" > bigpemu.desktop
chmod +x bigpemu.desktop
