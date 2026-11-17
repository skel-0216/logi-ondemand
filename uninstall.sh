#!/bin/bash
# Removes the watcher and the `logi` command. Logi Options+ itself is untouched.
set -u

PREFIX="${PREFIX:-$HOME/.local}"
LABEL="io.github.logi-ondemand"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
pkill -x logi-watch 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$PREFIX/bin/logi" "$PREFIX/bin/logi-watch"
rm -rf "$HOME/Library/Application Support/logi-ondemand"
echo "removed logi-ondemand."
echo "To let macOS start Logi Options+ at login again, re-enable it in"
echo "System Settings > General > Login Items & Extensions."
