#! /bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

WWW_DIR=/mnt/SDCARD/spruce/www

# Generic Startup
# Should only be used in contexts where firststart has already been called
start_darkhttpd_process() {
  if pgrep "darkhttpd" >/dev/null; then
    log_message "darkhttpd: Already running, skipping start" -v
    return 1
  fi

  if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 0 ]; then
    log_message "darkhttpd: WiFi is off, skipping start" -v
    return 2
  fi

  samba_enabled="$(get_config_value '.menuOptions."Network Settings".enableSamba.selected' "False")"
  ssh_enabled="$(get_config_value '.menuOptions."Network Settings".enableSSH.selected' "False")"
  sftpgo_enabled="$(get_config_value '.menuOptions."Network Settings".enableSFTPGo.selected' "False")"
  syncthing_enabled="$(get_config_value '.menuOptions."Network Settings".enableSyncthing.selected' "False")"

  # Check if at least one network service is enabled
  if [ "$syncthing_enabled" = "False" ] && \
     [ "$samba_enabled" = "False" ] && \
     [ "$ssh_enabled" = "False" ] && \
     [ "$sftpgo_enabled" = "False" ]; then
    log_message "darkhttpd: No network services enabled, skipping start" -v
    return 4
  fi

  log_message "darkhttpd: Starting Darkhttpd..."
  darkhttpd $WWW_DIR >/mnt/SDCARD/Saves/spruce/serve.log 2>&1 &
  return 0
}

stop_darkhttpd_process() {
  killall -9 darkhttpd
}
