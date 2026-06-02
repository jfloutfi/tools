#!/bin/bash

set -e

echo "Closing Steam if running..."
osascript -e 'tell application "Steam" to quit' 2>/dev/null || true
pkill -f Steam || true

echo "Removing Steam application..."
sudo rm -rf /Applications/Steam.app

echo "Removing Steam support files..."
rm -rf ~/Library/Application\ Support/Steam

echo "Removing caches..."
rm -rf ~/Library/Caches/com.valvesoftware.steam
rm -rf ~/Library/Caches/Steam

echo "Removing logs..."
rm -rf ~/Library/Logs/Steam

echo "Removing saved application state..."
rm -rf ~/Library/Saved\ Application\ State/com.valvesoftware.steam.savedState

echo "Removing preferences..."
rm -f ~/Library/Preferences/com.valvesoftware.steam.plist
rm -rf ~/Library/Preferences/ByHost/com.valvesoftware.steam.*

echo "Removing containers (if any)..."
rm -rf ~/Library/Containers/com.valvesoftware.steam

echo "Removing extra files (if any)..."
rm -rf /Users/joseph/Library/LaunchAgents/com.valvesoftware.steamclean.plist

echo "Searching for remaining Steam-related files..."
find ~/Library -iname "*steam*" 2>/dev/null

echo
echo "Steam cleanup complete."
echo "You may want to empty Trash and restart your Mac."