#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 \"Game Name\""
    exit 1
fi

GAME_NAME="$1"

find ~/Library -iname "*${GAME_NAME}*" 2>/dev/null