. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

HELPER_MESSAGE="For system notifications"

if [ "$IS_LOADING" = true ] ; then
    echo -n "$HELPER_MESSAGE"
    return 0
fi

if [ -z "$1" ]; then
    return 0
fi

# Strong
if [ "$1" == "0" ] ; then
    echo -n "$HELPER_MESSAGE"
    vibrate --intensity Strong &
    return 0
fi

# Medium
if [ "$1" == "1" ] ; then
    echo -n "$HELPER_MESSAGE"
    vibrate --intensity Medium &
    return 0
fi

# Weak
if [ "$1" == "2" ] ; then
    echo -n "$HELPER_MESSAGE"
    vibrate --intensity Weak &
    return 0
fi

# Off
if [ "$1" == "3" ] ; then
    echo -n "$HELPER_MESSAGE"
    return 0
fi
