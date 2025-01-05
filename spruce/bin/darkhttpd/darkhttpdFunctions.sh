#! /bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

DARKHTTPD_DIR=/mnt/SDCARD/spruce/bin/darkhttpd
WWW_DIR=/mnt/SDCARD/spruce/www

# Generic Statup
# Should only be used in contexts where firststart has already been called
start_darkhttpd_process() {
  if pgrep "darkhttpd" >/dev/null; then
    log_message "darkhttpd: Already running, skipping start"
    return
  fi

  log_message "darkhttpd: Starting Darkhttpd..."
  $DARKHTTPD_DIR/bin/darkhttpd $WWW_DIR >$DARKHTTPD_DIR/serve.log 2>&1 &
}

stop_darkhttpd_process() {
  killall -9 darkhttpd
}
