#!/bin/sh

if [ "$1" = "0" ]; then
    echo -n "Use Genesis Plus GX Wide core when available"
    return 0
elif [ "$1" = "1" ]; then
    echo -n "NOTE: Will only apply to widescreen devices (TrimUI Smart Pro)"
    return 0
fi