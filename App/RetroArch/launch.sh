#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

prepare_ra_config() {
	PLATFORM_CFG="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"
	if [ "$PLATFORM" = "Flip" ]; then
		CURRENT_CFG="/mnt/SDCARD/RetroArch/ra64.miyoo.cfg"
	else
		CURRENT_CFG="/mnt/SDCARD/RetroArch/retroarch.cfg"
	fi

	# Set auto save state based on spruceUI config
	auto_save="$(get_config_value '.menuOptions."Emulator Settings".raAutoSave.selected' "Custom")"
	log_message "auto save setting is $auto_save" -v
	if [ "$auto_save" = "True" ]; then
		TMP_CFG="$(mktemp)"
	    sed 's|^savestate_auto_save.*|savestate_auto_save = "true"|' "$PLATFORM_CFG" > "$TMP_CFG"
		mv "$TMP_CFG" "$PLATFORM_CFG"
	elif [ "$auto_save" = "False" ]; then
		TMP_CFG="$(mktemp)"
	    sed 's|^savestate_auto_save.*|savestate_auto_save = "false"|' "$PLATFORM_CFG" > "$TMP_CFG"
		mv "$TMP_CFG" "$PLATFORM_CFG"
	fi

	# Set auto load state based on spruceUI config
	auto_load="$(get_config_value '.menuOptions."Emulator Settings".raAutoLoad.selected' "Custom")"
	log_message "auto load setting is $auto_load" -v
	if [ "$auto_load" = "True" ]; then
		TMP_CFG="$(mktemp)"
	    sed 's|^savestate_auto_load.*|savestate_auto_load = "true"|' "$PLATFORM_CFG" > "$TMP_CFG"
		mv "$TMP_CFG" "$PLATFORM_CFG"
	elif [ "$auto_load" = "False" ]; then
		TMP_CFG="$(mktemp)"
	    sed 's|^savestate_auto_load.*|savestate_auto_load = "false"|' "$PLATFORM_CFG" > "$TMP_CFG"
		mv "$TMP_CFG" "$PLATFORM_CFG"
	fi

	# Set hotkey enable button based on spruceUI config
	case "$PLATFORM" in
		"Brick"|"SmartPro")
			hotkey_enable="$(get_config_value '.menuOptions."Emulator Settings".raHotkeyTrimUI.selected' "Menu")"
			;;
		"A30"|"Flip")
			hotkey_enable="$(get_config_value '.menuOptions."Emulator Settings".raHotkeyMiyoo.selected' "Select")"
			;;
	esac
	log_message "ra hotkey enable button is $hotkey_enable" -v
	case "$PLATFORM" in
		"A30")
			HOTKEY_LINE="input_enable_hotkey"
			SELECT_VAL="rctrl"
			START_VAL="enter"
			HOME_VAL="escape"
			;;
		*)
			HOTKEY_LINE="input_enable_hotkey_btn"
			SELECT_VAL="4"
			START_VAL="6"
			HOME_VAL="5"
			;;
	esac
	case "$hotkey_enable" in
		"Select")
			TMP_CFG="$(mktemp)"
			sed "s|^$HOTKEY_LINE = .*|$HOTKEY_LINE = \"$SELECT_VAL\"|" "$PLATFORM_CFG" > "$TMP_CFG"
			mv "$TMP_CFG" "$PLATFORM_CFG"
			;;
		"Start")
			TMP_CFG="$(mktemp)"
			sed "s|^$HOTKEY_LINE = .*|$HOTKEY_LINE = \"$START_VAL\"|" "$PLATFORM_CFG" > "$TMP_CFG"
			mv "$TMP_CFG" "$PLATFORM_CFG"
			;;
		"Menu")
			TMP_CFG="$(mktemp)"
			sed "s|^$HOTKEY_LINE = .*|$HOTKEY_LINE = \"$HOME_VAL\"|" "$PLATFORM_CFG" > "$TMP_CFG"
			mv "$TMP_CFG" "$PLATFORM_CFG"
		;;
		*) ;;
	esac
	# copy platform-specific RA config into place where RA wants it to be
	cp -f "$PLATFORM_CFG" "$CURRENT_CFG"
}

backup_ra_config() {
	# copy any changes to retroarch.cfg made during RA runtime back to platform-specific config
	PLATFORM_CFG="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"
	if [ "$PLATFORM" = "Flip" ]; then
		CURRENT_CFG="/mnt/SDCARD/RetroArch/ra64.miyoo.cfg"
	else
		CURRENT_CFG="/mnt/SDCARD/RetroArch/retroarch.cfg"
	fi
	[ -e "$CURRENT_CFG" ] && cp -f "$CURRENT_CFG" "$PLATFORM_CFG"
}

RA_DIR=/mnt/SDCARD/RetroArch
cd $RA_DIR/

case "$PLATFORM" in
	"A30") RA_BIN="ra32.miyoo" ;;
	"Flip") RA_BIN="ra64.miyoo" ;;
	"Brick"|"SmartPro"|"SmartProS") RA_BIN="ra64.trimui_$PLATFORM" ;;
esac

prepare_ra_config 2>/dev/null
HOME=$RA_DIR/ $RA_DIR/$RA_BIN -v
backup_ra_config 2>/dev/null

auto_regen_tmp_update