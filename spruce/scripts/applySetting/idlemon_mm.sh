#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

set_event_arg_for_idlemon

# Function to start idlemon based on idle_type and timeout_value
start_idlemon_poweroff() {
  local idle_type="$1"
  local timeout_value="$2"
  local idle_time=""
  local idle_count=""

  case "$idle_type" in
    in_menu)
      case "$timeout_value" in
        Off)
          pgrep -f 'idlemon.*MainUI.*poweroffAction.sh' | xargs kill -9
          return 0
          ;;
        2m)
          idle_time=120
          idle_count=10
          ;;
        5m)
          idle_time=300
          idle_count=20
          ;;
        10m)
          idle_time=600
          idle_count=40
          ;;
        *)
          return 1
          ;;
      esac
      # Kill all processes with 'idlemon' and 'MainUI' in the name
      pgrep -f 'idlemon.*MainUI.*poweroffAction.sh' | xargs kill -9

      # Start idlemon for in_menu with MainUI
      idlemon -p "MainUI" -t "$idle_time" -c "$idle_count" -s "/mnt/SDCARD/spruce/scripts/idlemon_poweroffAction.sh" -i $EVENT_ARG > /dev/null &
      ;;

    in_game)
      case "$timeout_value" in
        Off)
          pgrep -f 'idlemon.*miyoo.*poweroffAction.sh' | xargs kill -9
          return 0
          ;;
        2m)
          idle_time=120
          idle_count=10
          ;;
        5m)
          idle_time=300
          idle_count=20
          ;;
        10m)
          idle_time=600
          idle_count=40
          ;;
		    30m)
          idle_time=1800
          idle_count=300
          ;;
        *)
          return 1
          ;;
      esac
      # Kill all processes with 'idlemon' and 'miyoo' in the name
	    pgrep -f 'idlemon.*miyoo.*poweroffAction.sh' | xargs kill -9
	    # Start idlemon for in_game with multiple processes
      idlemon -p "ra32.miyoo,ra64.miyoo,ra64.trimui,drastic,PPSSPP,retroarch" -t "$idle_time" -c "$idle_count" -s "/mnt/SDCARD/spruce/scripts/idlemon_poweroffAction.sh" -i $EVENT_ARG > /dev/null &
      ;;

    *)
      echo "Unsupported idle type: $idle_type"
      return 1
      ;;
  esac
}

# Function to start idlemon based on idle_type and timeout_value
start_idlemon_charging() {
  local idle_type="$1"
  local timeout_value="$2"
  local idle_time=""
  local idle_count=""

  case "$idle_type" in
    in_menu)
      case "$timeout_value" in
        Off)
          echo "$timeout_value"
          pgrep -f 'idlemon.*MainUI.*chargingAction.sh' | xargs kill -9
          return 0
          ;;
        10s)
          idle_time=10
          idle_count=2
          ;;
        30s)
          idle_time=30
          idle_count=3
          ;;
        1m)
          idle_time=60
          idle_count=5
          ;;
        *)
          return 1
          ;;
      esac
      
      # Kill all processes with 'idlemon' and 'MainUI' in the name
      pgrep -f 'idlemon.*MainUI.*chargingAction.sh' | xargs kill -9

      # Start idlemon for in_menu with MainUI
      idlemon -p "MainUI" -t "$idle_time" -c "$idle_count" -s "/mnt/SDCARD/spruce/scripts/idlemon_chargingAction.sh" -i $EVENT_ARG > /dev/null &
      ;;

    in_game)
      case "$timeout_value" in
        Off)
          pgrep -f 'idlemon.*miyoo.*chargingAction.sh' | xargs kill -9
          return 0
          ;;
        30s)
          idle_time=30
          idle_count=3
          ;;
        1m)
          idle_time=60
          idle_count=5
          ;;
        5m)
          idle_time=300
          idle_count=20
          ;;
        10m)
          idle_time=600
          idle_count=40
          ;;
        *)
          return 1
          ;;
      esac

      # Kill all processes with 'idlemon' and 'miyoo' in the name
      pgrep -f 'idlemon.*miyoo.*chargingAction.sh' | xargs kill -9
      # Start idlemon for in_game with multiple processes
      idlemon -p "ra32.miyoo,ra64.miyoo,ra64.trimui,drastic,PPSSPP,retroarch" -t "$idle_time" -c "$idle_count" -s "/mnt/SDCARD/spruce/scripts/idlemon_chargingAction.sh" -i $EVENT_ARG > /dev/null &
      ;;

    *)
      echo "Unsupported idle type: $idle_type"
      return 1
      ;;
  esac
}

# Main script logic
# Handle in_menu poweroff setting
IDLE_MENU_POWEROFF_VALUE="$(get_config_value '.menuOptions."Battery Settings".idlemonInMenu.selected' "5m")"
start_idlemon_poweroff "in_menu" "$IDLE_MENU_POWEROFF_VALUE"

# Handle in_game poweroff setting
IDLE_GAME_POWEROFF_VALUE="$(get_config_value '.menuOptions."Battery Settings".idlemonInGame.selected' "Off")"
start_idlemon_poweroff "in_game" "$IDLE_GAME_POWEROFF_VALUE"

# Handle in_menu charging setting
IDLE_MENU_CHARGING_VALUE="$(get_config_value '.menuOptions."Battery Settings".idlemonChargingInMenu.selected' "Off")"
start_idlemon_charging "in_menu" "$IDLE_MENU_CHARGING_VALUE"

# Handle in_game charging setting
IDLE_GAME_CHARGING_VALUE="$(get_config_value '.menuOptions."Battery Settings".idlemonChargingInGame.selected' "Off")"
start_idlemon_charging "in_game" "$IDLE_GAME_CHARGING_VALUE"
