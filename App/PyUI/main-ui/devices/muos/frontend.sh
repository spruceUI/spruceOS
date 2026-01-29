#!/bin/sh

. /opt/muos/script/var/func.sh

ACT_GO=/tmp/act_go
APP_GO=/tmp/app_go
GOV_GO=/tmp/gov_go
CON_GO=/tmp/con_go
ROM_GO=/tmp/rom_go

EX_CARD=/tmp/explore_card

MUX_AUTH=/tmp/mux_auth
MUX_LAUNCHER_AUTH=/tmp/mux_launcher_auth

SKIP=0

if [ -n "$1" ]; then
	ACT="$1"
	SKIP=1
else
	ACT=$(GET_VAR "config" "settings/general/startup")
fi
printf '%s\n' "$ACT" >"$ACT_GO"

echo "root" >$EX_CARD

LAST_APP_FILE="/opt/muos/config/boot/last_app"
if [ -f "$LAST_APP_FILE" ]; then
	LAST_APP=$(cat "$LAST_APP_FILE")
	LOG_INFO "$0" 0 "FRONTEND" "LAST_APP read as '${LAST_APP}'"
else
	LOG_INFO "$0" 0 "FRONTEND" "${LAST_APP_FILE} does not exist"
    LAST_APP=""
fi


LAST_PLAY=$(cat "/opt/muos/config/boot/last_play")

LOG_INFO "$0" 0 "FRONTEND" "Setting default CPU governor"
SET_DEFAULT_GOVERNOR

handle_app_go() {
    # Only proceed if the APP_GO file exists and is not empty
    if [ -s "$APP_GO" ]; then
        # Read app name
        IFS= read -r RUN_APP <"$APP_GO"

        # Save last run app
        echo "$RUN_APP" >"$LAST_APP_FILE"

        ENSURE_REMOVED "$APP_GO"

        "$RUN_APP"/mux_launch.sh "$RUN_APP"
        echo appmenu >$ACT_GO

        LOG_INFO "$0" 0 "FRONTEND" "Clearing Governor and Control Scheme files"
        [ -e "$GOV_GO" ] && ENSURE_REMOVED "$GOV_GO"
        [ -e "$CON_GO" ] && ENSURE_REMOVED "$CON_GO"

        LOG_INFO "$0" 0 "FRONTEND" "Setting Governor back to default"
        SET_DEFAULT_GOVERNOR
    fi
}

restore_app_or_game_cleanup() {
	# We'll set a few extra things here so that the user doesn't get
	# a stupid "yOu UsEd tHe ReSeT bUtToN" message because ultimately
	# we don't really care in this particular instance...
	[ -e "/tmp/safe_quit" ] && ENSURE_REMOVED "/tmp/safe_quit"
	[ ! -e "/tmp/done_reset" ] && printf 1 >"/tmp/done_reset"
	[ ! -e "/tmp/chime_done" ] && printf 1 >"/tmp/chime_done"
	SET_VAR "config" "system/used_reset" 0

	# Reset audio control status
	RESET_AMIXER


}

#:] ### Wait for audio stack
#:] Don't proceed to the frontend until PipeWire reports that it is ready.
LOG_INFO "$0" 0 "BOOTING" "Waiting for Pipewire Init"
until [ "$(GET_VAR "device" "audio/ready")" -eq 1 ]; do TBOX sleep 0.01; done


# If you want to keep pm_libs on the sdcard
if [ -d /mnt/sdcard/pm_libs ]; then
    mkdir -p /mnt/mmc/MUOS/PortMaster/libs
    mount --bind /mnt/sdcard/pm_libs /mnt/mmc/MUOS/PortMaster/libs
fi

if [ $SKIP -eq 0 ]; then
	LOG_INFO "$0" 0 "FRONTEND" "Checking for last or resume startup"
	if [ "$(GET_VAR "config" "settings/general/startup")" = "last" ] || [ "$(GET_VAR "config" "settings/general/startup")" = "resume" ]; then
		GO_LAST_BOOT=1

		if [ -n "$LAST_PLAY" ]; then
			LOG_INFO "$0" 0 "FRONTEND" "Checking for network and retrowait"

			if [ "$(GET_VAR "config" "settings/advanced/retrowait")" -eq 1 ]; then
				NET_START="/tmp/net_start"
				OIP=0

				while :; do
					NW_MSG=$(printf "Waiting for network to connect... (%s)\n\nPress START to continue loading\nPress SELECT to go to main menu" "$OIP")
					/opt/muos/frontend/muxmessage 0 "$NW_MSG"
					OIP=$((OIP + 1))

					if [ "$(cat "$(GET_VAR "device" "network/state")")" = "up" ]; then
						LOG_SUCCESS "$0" 0 "FRONTEND" "Network connected"
						/opt/muos/frontend/muxmessage 0 "Network connected"

						PIP=0
						while ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; do
							PIP=$((PIP + 1))
							LOG_INFO "$0" 0 "FRONTEND" "Verifying connectivity..."
							/opt/muos/frontend/muxmessage 0 "Verifying connectivity... (%s)" "$PIP"
							TBOX sleep 1
						done

						LOG_SUCCESS "$0" 0 "FRONTEND" "Connectivity verified! Booting content!"
						/opt/muos/frontend/muxmessage 0 "Connectivity verified! Booting content!"

						GO_LAST_BOOT=1
						break
					fi

					if [ "$(cat "$NET_START")" = "ignore" ]; then
						LOG_SUCCESS "$0" 0 "FRONTEND" "Ignoring network connection"
						/opt/muos/frontend/muxmessage 0 "Ignoring network connection... Booting content!"

						GO_LAST_BOOT=1
						break
					fi

					if [ "$(cat "$NET_START")" = "menu" ]; then
						LOG_SUCCESS "$0" 0 "FRONTEND" "Booting to main menu"
						/opt/muos/frontend/muxmessage 0 "Booting to main menu!"

						GO_LAST_BOOT=0
						break
					fi

					TBOX sleep 1
				done
			fi

			if [ $GO_LAST_BOOT -eq 1 ]; then
				LOG_INFO "$0" 0 "FRONTEND" "Booting to last launched content"
				cat "$LAST_PLAY" >"$ROM_GO"

				BASE="$(basename "$LAST_PLAY" .cfg)"
				DIR="$(dirname "$LAST_PLAY")"

				for TYPE in "governor" "control scheme"; do
					case "$TYPE" in
						"governor")
							CONTENT_FILE="${DIR}/${BASE}.gov"
							FALLBACK_FILE="${DIR}/core.gov"
							OUTPUT_FILE="$GOV_GO"
							;;
						"control scheme")
							CONTENT_FILE="${DIR}/${BASE}.con"
							FALLBACK_FILE="${DIR}/core.con"
							OUTPUT_FILE="$CON_GO"
							;;
					esac

					if [ -e "$CONTENT_FILE" ]; then
						cat "$CONTENT_FILE" >"$OUTPUT_FILE"
					elif [ -e "$FALLBACK_FILE" ]; then
						cat "$FALLBACK_FILE" >"$OUTPUT_FILE"
					else
						LOG_INFO "$0" 0 "FRONTEND" "No ${TYPE} file found for launched content"
					fi
				done

				restore_app_or_game_cleanup

				# Okay we're all set, time to launch whatever we were playing last
				/opt/muos/script/mux/launch.sh
			fi
		fi

		echo launcher >$ACT_GO
    elif [ "$(GET_VAR "config" "settings/general/startup")" = "lastapp" ]; then
        LOG_INFO "$0" 0 "FRONTEND" "Startup is last app and LAST_APP is ${LAST_APP}"
        # Check if LAST_APP is not an empty string
        if [ -n "$LAST_APP" ]; then
			restore_app_or_game_cleanup
            # Write LAST_APP to the file path stored in $APP_GO
            echo "$LAST_APP" > "$APP_GO"
            echo app >"$ACT_GO"

            # Call the function to handle APP_GO
            handle_app_go
        fi
	fi
fi

cp /opt/muos/log/*.log "$(GET_VAR "device" "storage/rom/mount")/MUOS/log/boot/." &

LOG_INFO "$0" 0 "FRONTEND" "Starting Frontend Launcher"

read -r START_TIME _ </proc/uptime
SET_VAR "system" "start_time" "$START_TIME"

while :; do
	killall -9 "gptokeyb" "gptokeyb2" >/dev/null 2>&1

	# Reset ANALOGUE<>DIGITAL switch for the DPAD
	case "$(GET_VAR "device" "board/name")" in
		rg*) echo 0 >"/sys/class/power_supply/axp2202-battery/nds_pwrkey" ;;
		tui*)
			DPAD_FILE="/tmp/trimui_inputd/input_dpad_to_joystick"
			[ -e "$DPAD_FILE" ] && ENSURE_REMOVED "$DPAD_FILE"
			;;
		*) ;;
	esac

	# Reset audio control status
	RESET_AMIXER

	# Content Loader
	[ -s "$ROM_GO" ] && /opt/muos/script/mux/launch.sh

	[ -s "$ACT_GO" ] && {
		IFS= read -r ACTION <"$ACT_GO"

		LOG_INFO "$0" 0 "FRONTEND" "$(printf "Loading '%s' Action" "$ACTION")"

		case "$ACTION" in
			"launcher")
				LOG_INFO "$0" 0 "FRONTEND" "Clearing Governor and Control Scheme files"
				[ -e "$GOV_GO" ] && ENSURE_REMOVED "$GOV_GO"
				[ -e "$CON_GO" ] && ENSURE_REMOVED "$CON_GO"

				LOG_INFO "$0" 0 "FRONTEND" "Setting Governor back to default"
				SET_DEFAULT_GOVERNOR

				touch /tmp/pdi_go

				EXEC_MUX "launcher" "muxfrontend"
				;;

			"explore") EXEC_MUX "explore" "muxfrontend" ;;

			"app")
				if [ -s "$APP_GO" ]; then
					handle_app_go
				fi
				;;

			"appmenu")
				LOG_INFO "$0" 0 "FRONTEND" "Clearing Governor and Control Scheme files"
				[ -e "$GOV_GO" ] && ENSURE_REMOVED "$GOV_GO"
				[ -e "$CON_GO" ] && ENSURE_REMOVED "$CON_GO"

				LOG_INFO "$0" 0 "FRONTEND" "Setting Governor back to default"
				SET_DEFAULT_GOVERNOR

				EXEC_MUX "app" "muxfrontend"
				;;

			"collection") EXEC_MUX "collection" "muxfrontend" ;;

			"history") EXEC_MUX "history" "muxfrontend" ;;

			"info") EXEC_MUX "info" "muxfrontend" ;;

			"credits")
				/opt/muos/bin/nosefart "$MUOS_SHARE_DIR/media/support.nsf" &
				EXEC_MUX "info" "muxcredits"
				pkill -9 -f "nosefart" &
				;;

			"reboot")
				PLAY_SOUND reboot
				/opt/muos/script/mux/quit.sh reboot frontend
				;;

			"shutdown")
				PLAY_SOUND shutdown
				/opt/muos/script/mux/quit.sh poweroff frontend
				;;

			*)
				printf "Unknown Module: %s\n" "$ACTION" >&2
				EXEC_MUX "$ACTION" "muxfrontend"
				;;
		esac
	}

done
