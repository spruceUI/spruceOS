cd /mnt/SDCARD/App/Syncthing/
export sysdir=/mnt/SDCARD/.tmp_update
export miyoodir=/mnt/SDCARD/miyoo
export LD_LIBRARY_PATH="/mnt/SDCARD/App/Syncthing/lib:/lib:/config/lib:$miyoodir/lib:$sysdir/lib:$sysdir/lib/parasyte"
export PATH="$sysdir/bin:$PATH"

if ! pgrep "syncthing" > /dev/null; then
    /mnt/SDCARD/App/Syncthing/bin/syncthing serve --home=/mnt/SDCARD/App/Syncthing/config/ > /mnt/SDCARD/App/Syncthing/serve.log 2>&1 &
fi