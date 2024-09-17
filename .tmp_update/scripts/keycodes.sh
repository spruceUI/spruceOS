#!/bin/sh

# exports needed so we can call this function using more memorable button names

export B_LEFT="key 1 105"
export B_RIGHT="key 1 106"
export B_UP="key 1 103"
export B_DOWN="key 1 108"

export B_A="key 1 57"
export B_B="key 1 29"
export B_X="key 1 42"
export B_Y="key 1 56"

export B_L1="key 1 15"
export B_L2="key 1 18"
export B_R1="key 1 14"
export B_R2="key 1 20"

export B_START="key 1 28"
export B_START_2="enter_pressed" # only registers 0 on release, no 1 on press
export B_SELECT="key 1 97"
export B_SELECT_2="rctrl_pressed"

export B_VOLUP="volume up" # only registers on press and on change, not on release. No 1 or 0.
export B_VOLDOWN="key 1 114" # has actual key codes like the buttons
export B_VOLDOWN_2="volume down" # only registers on change. No 1 or 0.
export B_MENU="key 1 1" # surprisingly functions like a regular button
# export B_POWER # too complicated to bother with tbh

# export PRESS=1
# export RELEASE=0


exec_on_hotkey() {

	cmd="$1"
	key1="$2"
	key2="$3"
	key3="$4"
	key4="$5"
	key5="$6"

	key1_pressed=0
	key2_pressed=0
	key3_pressed=0
	key4_pressed=0
	key5_pressed=0
	
	num_keys="$#"
	num_keys=$((num_keys - 1))
	count=0
	messages_file="/var/log/messages"
	
	while [ 1 ]; do
	
	    	last_line=$(tail -n 1 "$messages_file")
	    	
	    	case "$last_line" in
	        	*"$key1 1"*)
	            	key1_pressed=1
	            	;;
	        	*"$key1 0"*)
	            	key1_pressed=0
	            	;;
		esac
		count="$key1_pressed"
			
		if [ "$#" -gt 2 ]; then
			case "$last_line" in
	        		*"$key2 1"*)
	            		key2_pressed=1
	            		;;
	        		*"$key2 0"*)
	            		key2_pressed=0
	            		;;
			esac
			count=$((count + key2_pressed))
		fi
			
		if [ "$#" -gt 3 ]; then
			case "$last_line" in
	        		*"$key3 1"*)
	            		key3_pressed=1
	            		;;
	        		*"$key3 0"*)
	            		key3_pressed=0
	            		;;
			esac
			count=$((count + key3_pressed))
		fi
			
		if [ "$#" -gt 4 ]; then
			case "$last_line" in
	        		*"$key4 1"*)
	            		key4_pressed=1
	            		;;
	        		*"$key4 0"*)
	            		key4_pressed=0
	            		;;
			esac
			count=$((count + key4_pressed))
		fi
			
		if [ "$#" -gt 5 ]; then
		    	case "$last_line" in
	        		*"$key5 1"*)
	            		key5_pressed=1
	            		;;
	        		*"$key5 0"*)
	            		key5_pressed=0
	            		;;
			esac
			count=$((count + key5_pressed))
		fi
		
# make sure count doesn't go beyond bounds for some reason.
		if [ $count -lt 0 ]; then
			count=0
		elif [ $count -gt "$num_keys" ]; then
			count="$num_keys"
		fi
		
# if all designated keys depressed, do the thing!	
		if [ $count -eq "$num_keys" ]; then
			"$cmd"
			break
		fi
		
	done
}
