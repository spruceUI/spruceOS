#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

set_event_arg_for_idlemon

idle_type="$1"
timeout_value="$2"

# Function to start idlemon based on idle_type and timeout_value
start_idlemon() {
  idle_type="$1"
  timeout_value="$2"
  idle_time=""
  idle_count=""

  case "$idle_type" in
    in_menu)
      case "$timeout_value" in
        Off)
		      pgrep -f 'idlemon.*MainUI' | xargs kill -9
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
      pgrep -f 'idlemon.*MainUI' | xargs kill -9

      # Start idlemon for in_menu with MainUI
      idlemon -p "MainUI" -t "$idle_time" -c "$idle_count" -s "/mnt/SDCARD/spruce/scripts/idlemon_actionWrapper.sh" -i $EVENT_ARG > /dev/null &
      ;;

    in_game)
      case "$timeout_value" in
         Off)
		      pgrep -f 'idlemon.*miyoo' | xargs kill -9
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
	    pgrep -f 'idlemon.*miyoo' | xargs kill -9
	    # Start idlemon for in_game with multiple processes
      idlemon -p "ra32.miyoo,ra64.miyoo,ra64.trimui,drastic,PPSSPP,retroarch" -t "$idle_time" -c "$idle_count" -s "/mnt/SDCARD/spruce/scripts/idlemon_actionWrapper.sh" -i $EVENT_ARG > /dev/null &
      ;;

    *)
      echo "Unsupported idle type: $idle_type"
      return 1
      ;;
  esac
}

# Function to reapply both settings
reapply_settings() {
  # Handle in_menu setting
  IDLE_MENU_VALUE="$(get_config_value '.menuOptions."Battery Settings".idlemonInMenu.selected' "5m")"

  start_idlemon "in_menu" "$IDLE_MENU_VALUE"

  # Handle in_game setting
  IDLE_GAME_VALUE="$(get_config_value '.menuOptions."Battery Settings".idlemonInGame.selected' "Off")"

  start_idlemon "in_game" "$IDLE_GAME_VALUE"
}

# Main script logic
case "$1" in
    "reapply")
        reapply_settings
        ;;
    *)
        if [ -z "$idle_type" ]; then
            reapply_settings
        else
            # If idle_type is provided but no timeout_value, fetch from settings
            if [ -z "$timeout_value" ]; then
                case "$idle_type" in
                    in_menu)
                        timeout_value="$(get_config_value '.menuOptions."Battery Settings".idlemonInMenu.selected' "5m")"
                        ;;
                    in_game)
                        timeout_value="$(get_config_value '.menuOptions."Battery Settings".idlemonInGame.selected' "Off")"
                        ;;
                    *)
                        log_message "Unsupported idle type: $idle_type"
                        exit 1
                        ;;
                esac
            fi
            start_idlemon "$idle_type" "$timeout_value"
        fi
        ;;
esac
