#!/bin/sh

# Prints a RetroAchievements session token for the account, or nothing.
rac_login_token() {
	_u="$(printf '%s' "$1" | sed 's/%/%25/g; s/+/%2B/g; s/#/%23/g; s/&/%26/g; s/ /%20/g')"
	_p="$(printf '%s' "$2" | sed 's/%/%25/g; s/+/%2B/g; s/#/%23/g; s/&/%26/g; s/ /%20/g')"
	_url="https://retroachievements.org/dorequest.php?r=login&u=$_u&p=$_p"
	if command -v curl >/dev/null 2>&1; then
		_resp="$(curl -sS -f --connect-timeout 15 -A spruceOS "$_url" 2>/dev/null)"
		case "$?" in
			35|51|58|59|60|77) _resp="$(curl -k -sS -f --connect-timeout 15 -A spruceOS "$_url" 2>/dev/null)" ;;
		esac
	else
		_resp="$(wget -q --no-check-certificate -U spruceOS -O - "$_url" 2>/dev/null)"
	fi
	printf '%s' "$_resp" | sed -n 's/.*"Token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}
