# CHAI Retrofit 
I made a proposal for a standardized way cfw expose controls/events to applications to enable easier development of applications on arm devices. People are hard to influence though so instead of harrassing various CFW maintainers I made this retrofit library that app devs can ship with their app for a similar result. 

If chai_retrofit is being used on cfw that actually does implement CHAI then chai_retrofit gets ignored and defers to the CFW. The original proposal doc is at the bottom of this README.

Edit: Don't feel pressure to use this, it can just be educational, I'm thrilled if this saves anyone some time digging through firmware code

## How to use it

### 1. Ship it with your app

Copy this repo into your port's folder, or add it as a git submodule:

```sh
git submodule add git@github.com:Songo-Player/chai_retrofit.git yourport/chai_retrofit
```

If you zip your port up, skip the submodule's `.git` file. Keep the executable bits on `bin/chai`, the `*/vol_listener` files and `NextUI/backlight`.

### 2. Source it from your launch script

Source `chai_entry.sh` before starting your app, and call `chai_retrofit_teardown` after it exits. It works from PortMaster launchers and from a CFW's own app launchers: it recognizes the CFW by files the CFW ships (version files, `/etc/os-release`), not by PortMaster's `CFW_NAME`.

```bash
#!/bin/bash
source "$controlfolder/control.txt"   # PortMaster, sets GAMEDIR etc. (not needed by chai)

CHAI_RETRO_DIR="$GAMEDIR/chai_retrofit"   # optional in bash, needed in other shells
source "$GAMEDIR/chai_retrofit/chai_entry.sh"

./your_app

chai set-idle-suppression 0 2>/dev/null   # in case the app exited with it on
chai_retrofit_teardown
```

`chai_entry.sh` checks for a `chai` command first. If the CFW ships one, it does nothing else. Otherwise it picks a profile for the CFW, runs that profile's setup (anything it needs to watch volume changes, like a wrapper or listener), and puts `bin/chai` on `PATH`. `chai_retrofit_teardown` undoes that setup, and does nothing when the CFW has its own chai.

Your app, and anything it starts, inherits the updated `PATH`.

### 3. Call `chai` from your app

Every command from the proposal below works the same way whether the CFW implements CHAI or the retrofit is filling in:

```sh
chai get-brightness              # 0-255
chai set-brightness 0            # 0 turns the screen off
chai get-battery-percent         # 0-100
chai get-battery-status          # 1 charging, 0 otherwise
chai set-idle-suppression 1      # no idle dim/sleep or lid-close sleep
chai get-path roms
```

Check whether `chai` exists before relying on it (eg: `command -v chai`), so your app still runs if it was launched without the retrofit. A command that isn't supported prints nothing and exits non-zero, so treat empty output as "not available".

### Volume subscribers

To react to volume changes (eg: to draw a volume overlay), register an executable script:

```sh
chai add-volume-subscriber "$GAMEDIR/on_volume.sh"
# ...on exit:
chai remove-volume-subscriber "$GAMEDIR/on_volume.sh"
```

chai runs it in the background on every volume change, including presses at the min or max, as:

```sh
on_volume.sh VOLUME MAX
```

`MAX` is usually 100. It's higher when the CFW allows volume boost (eg: 200 with MustardOS overdrive), so scale `VOLUME` by `MAX` rather than assuming a percent. Subscriber scripts should be quick, since holding a volume key sends many updates. Subscriptions don't survive a reboot.

### Supported CFWs

| Profile | CFW | Notes |
|---|---|---|
| `MustardOS` | MustardOS | Andromeda (2606) and older |
| `knulli` | Knulli | Scarab and older (batocera-* era) |
| `ROCKNIX` | ROCKNIX, JELOS | JELOS untested |
| `ArkOS` | ArkOS, dArkOS | Untested. Root steps use `sudo -n` (ports run as `ark`). Volume through an `amixer` wrapper; idle suppression through `processcheck.sh`. No lid or power-button handling |
| `TrimUI` | TrimUI stock, CrossMix | Untested. Idle suppression isn't possible (MainUI is closed source). Volume from `/tmp/system/set_volume`, min/max presses not reported |
| `NextUI` | NextUI | |
| `Spruce` | Spruce | |
| `default` | Anything else | Generic sysfs backlight, battery and lid sensor, and a PipeWire wrapper for volume. `get-path` isn't supported |

Each profile's `chai.sh` overrides only what its CFW does differently and falls back to `default/chai.sh` for the rest. To add a CFW, copy an existing profile folder, override the functions you need, and add a detection case to `_chai_detect_profile` in `chai_entry.sh` that checks for a file only that CFW ships.

---

## Help me kill chai_retrofit
Chai retrofit has to do some invasive stuff like mount binding over volume scripts or temporarily writing over cfw config files, its ugly and it feels bad. If CFW projects implement CHAI then these ugly parts fit gracefully in the cfw without being forced. If you maintain/contribute to a cfw project let me know how we can make CHAI a better interface and implement it yourself so app devs aren't tempted to use chai_retrofit

## AI Usage Disclosure (1 out of 5 🤖)
I used claude to help port existing cfw strategies I made for songo to match the chai proposal which I wrote myself.

---
# Original CHAI Proposal:

## C.H.A.I (Common Handheld Application Interface)

An interface that various cfw's can implement that allows application developers to safely interact with the cfw in a standardized and clean way.

## Why do we need CHAI?

More and more apps are being developed that try to behave like native applications and they interact with cfw in increasingly unique ways. Songo#5, Rockbox, and other media players have a tendency to include a screen fade, suppress idle behavior, ignore clamshell lid closure, monitor volume adjustments. Each of these behaviors is implemented differently on a per cfw (and sometimes per cfw version) basis. It is messy and also can include code that the original cfw devs may not want around, EG: In songo I mount/bind over volume scripts to intercept changes and render a volume widget.

If CFW's implement their own CHAI interface then application development is unblocked in a major way and devs can focus on actual application code instead of creating an evergrowing strategy pattern mess. Also we can allow the risky code to be governed entirely by cfw maintainers removing the need for costly polling or mount/binding.

## How do app devs use CHAI?

Here is a rough draft of the methods I'm proposing for CHAI implementation. Note that many of these would just be alias's for the host cfw's own internal scripts

| Function | Description |
|---|---|
| `chai get-brightness` | return brightness as 0-255 |
| `chai set-brightness 50` | takes any val 0-255, turn of screen when set to 0 if applicable |
| `chai get-battery-percent` | return battery percent as num between 0-100 |
| `chai get-battery-status` | return "0" for not charging, "1" for charging |
| `chai set-idle-suppression 1` | takes 1 or 0, should act like "caffienate" ignoring the cfws standard idle behavior. This should also prevent sleep in clamshell lid closure.<br><br>**This is potentially the most involved function to implement** |
| `chai add-volume-subscriber "./update_volume_widget.sh"` | takes a path param, cfw will pass vol updates to registered subscriber scripts. |
| `chai remove-volume-subscriber "./update_volume_widget.sh"` | Removes subscriber path |
| `chai get-path "userdata"` | Accepts various options to get cfw specific directories. Options may include "userdata", "screenshots", "roms", "media", etc… |

## What does CHAI look like?

CHAI should be using host cfw functions as much as possible, implementing CHAI for any given cfw should be fairly straight forward. Here is a partial example for MustardOS.

```sh
#!/bin/sh
# chai for MustardOS 2606.0 "Andromeda"
#
# Install: /opt/muos/script/system/chai.sh, symlinked to /usr/bin/chai
# Volume subscribers and idle suppression need the small MustardOS patches in
# muos-andromeda.patch, next to this file.

. /opt/muos/script/var/base.sh
. /opt/muos/script/var/config.sh
. /opt/muos/script/var/service.sh # CAFFEINE on|off

CHAI_VOL_SUBS="$MUOS_RUN_DIR/chai/volume_subscribers"

# MustardOS brightness is already 0-255 on every Andromeda device (device/common/config/screen/bright)
chai_get_brightness() {
	# bright.sh creates /tmp/mux_blank when the screen is off
	[ -e /tmp/mux_blank ] && echo 0 && return
	GET_VAR "config" "settings/general/brightness"
	echo
}

# bright.sh handles board quirks and blanks the screen at 0
chai_set_brightness() {
	/opt/muos/script/device/bright.sh "$1"
}

chai_get_battery_percent() {
	cat "$MUOS_RUN_DIR/battery/capacity"
}

chai_get_battery_status() {
	[ "$(cat "$MUOS_RUN_DIR/battery/charging")" = "0" ] && echo 0 || echo 1
}

# Uses MustardOS's own caffeine flag. hotkey.sh's SLEEP() already checks it, which
# blocks idle sleep and lid-close sleep. The patch adds the idle screen dim.
chai_set_idle_suppression() {
	case "$1" in
		1) CAFFEINE on ;;
		0) CAFFEINE off ;;
	esac
}

# Subscribers run as: <path> VOLUME MAX   (MAX is 100, or 200 with overdrive)
chai_add_volume_subscriber() {
	# Store the full path; subscribers run from audio.sh's directory, not the app's
	SUB="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
	mkdir -p "${CHAI_VOL_SUBS%/*}"
	touch "$CHAI_VOL_SUBS"
	grep -qxF "$SUB" "$CHAI_VOL_SUBS" || echo "$SUB" >>"$CHAI_VOL_SUBS"
}

chai_remove_volume_subscriber() {
	SUB="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
	[ -f "$CHAI_VOL_SUBS" ] || return 0
	grep -vxF "$SUB" "$CHAI_VOL_SUBS" >"$CHAI_VOL_SUBS.tmp"
	mv -f "$CHAI_VOL_SUBS.tmp" "$CHAI_VOL_SUBS"
}

# Internal: called by the patched audio.sh on every volume change
chai_notify_volume() {
	while IFS= read -r SUB; do
		[ -x "$SUB" ] && "$SUB" "$1" "$2" </dev/null >/dev/null 2>&1 &
	done <"$CHAI_VOL_SUBS"
}

# /run/muos/storage paths are bind-mounted by MustardOS to whichever SD card holds them
chai_get_path() {
	case "$1" in
		userdata) echo "$MUOS_STORE_DIR" ;;
		screenshots) echo "$MUOS_STORE_DIR/screenshot" ;;
		media) echo "$MUOS_STORE_DIR/music" ;;
		roms) echo "$(GET_VAR "device" "storage/rom/mount")/ROMS" ;;
		*) return 1 ;;
	esac
}

chai_usage() {
	cat >&2 <<EOF
usage: chai <command> [args]

commands:
  get-brightness
  set-brightness N               (N = 0-255)
  get-battery-percent
  get-battery-status
  set-idle-suppression N         (N = 0 or 1)
  add-volume-subscriber path
  remove-volume-subscriber path
  get-path name                  (userdata, screenshots, media, roms)
EOF
}

chai_main() {
	cmd=$1
	[ $# -gt 0 ] && shift
	case $cmd in
		get-brightness) chai_get_brightness ;;
		set-brightness) chai_set_brightness "$@" ;;
		get-battery-percent) chai_get_battery_percent ;;
		get-battery-status) chai_get_battery_status ;;
		set-idle-suppression) chai_set_idle_suppression "$@" ;;
		add-volume-subscriber) chai_add_volume_subscriber "$@" ;;
		remove-volume-subscriber) chai_remove_volume_subscriber "$@" ;;
		get-path) chai_get_path "$@" ;;
		notify-volume) chai_notify_volume "$@" ;;
		*)
			chai_usage
			exit 1
			;;
	esac
}

chai_main "$@"
```