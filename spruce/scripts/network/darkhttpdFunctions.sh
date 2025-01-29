#! /bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/settings/platform/$PLATFORM.cfg

if [ "$PLATFORM" = "A30" ]; then
  DARKHTTPD_DIR=/mnt/SDCARD/spruce/bin/darkhttpd
else
  DARKHTTPD_DIR=/mnt/SDCARD/spruce/bin64/darkhttpd
fi

WWW_DIR=/mnt/SDCARD/spruce/www

# Generic Startup
# Should only be used in contexts where firststart has already been called
start_darkhttpd_process() {
  if pgrep "darkhttpd" >/dev/null; then
    log_message "darkhttpd: Already running, skipping start" -v
    return
  fi

  wifi=$(grep '"wifi"' $SYSTEM_JSON | awk -F ':' '{print $2}' | tr -d ' ,')
  if [ "$wifi" -eq 0 ]; then
    log_message "darkhttpd: WiFi is off, skipping start" -v
    return
  fi

  # Check if at least one network service is enabled
  if ! (setting_get "samba" || setting_get "dropbear" || setting_get "sftpgo" || setting_get "syncthing"); then
    log_message "darkhttpd: No network services enabled, skipping start" -v
    return
  fi

  log_message "darkhttpd: Starting Darkhttpd..."
  $DARKHTTPD_DIR/bin/darkhttpd $WWW_DIR >$DARKHTTPD_DIR/serve.log 2>&1 &
}

stop_darkhttpd_process() {
  killall -9 darkhttpd
}
