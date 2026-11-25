#!/bin/bash

# Sourced by Songo5.sh before Godot starts.
#
# Music plays in SongoBGPlayer's songo_bgplayer daemon (next to the runtime,
# in runtime/), which Songo starts and controls. "Quit with Music" leaves it playing after
# Songo exits (idle suppression is turned off either way). It's left running
# here so Songo can pick its queue back up on boot, which turns idle
# suppression back on.
#
# Godot and the daemon both have the sound device open while Songo runs, so
# this needs a sound server (PipeWire or PulseAudio) to share it.

# Tells Godot background playback is available, enabling "Quit with Music"
SONGO_SBC_BG_PLAY="1"
# Where the daemon listens. Its lock file next to it holds its PID.
SONGO_PLAYER_SOCKET="/tmp/songo_player.sock"

# The daemon's PID if it's running, checked by name as a stale lock file's PID
# may belong to something else by now
songo_player_pid() {
	local pid
	pid="$(cat "${SONGO_PLAYER_SOCKET}.lock" 2>/dev/null)"
	if [ -n "$pid" ] && cat "/proc/${pid}/cmdline" 2>/dev/null | tr '\0' ' ' | grep -q songo_bgplayer; then
		echo "$pid"
	fi
}

SONGO_PLAYER_PID="$(songo_player_pid)"
if [ -n "$SONGO_PLAYER_PID" ]; then
	echo "Music player left playing (PID ${SONGO_PLAYER_PID}), Songo will pick it up"
fi

# ALSA's "default" isn't always routed through the sound server, while these
# are when they exist
SONGO_AUDIO_DEVICE=""
if command -v aplay >/dev/null 2>&1; then
	SONGO_ALSA_DEVICES="$(aplay -L 2>/dev/null)"
	for DEVICE in pipewire pulse; do
		# A whole line of the list, as "grep -x" would match
		case "
${SONGO_ALSA_DEVICES}
" in
			*"
${DEVICE}
"*)
				SONGO_AUDIO_DEVICE="$DEVICE"
				break
				;;
		esac
	done
	unset SONGO_ALSA_DEVICES
fi
if ! pgrep -x 'pipewire|pulseaudio' >/dev/null 2>&1; then
	echo "WARNING: No sound server running, music and Songo's sounds may not play together"
fi
echo "Music player ALSA device: ${SONGO_AUDIO_DEVICE:-default}"

export SONGO_SBC_BG_PLAY
export SONGO_PLAYER_SOCKET
export SONGO_AUDIO_DEVICE
