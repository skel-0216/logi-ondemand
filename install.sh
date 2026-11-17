#!/bin/bash
# Installs `logi` and the background watcher (per-user, no sudo).
#
#   ./install.sh            event mode: start on connect, stop 10 min after disconnect
#   ./install.sh --light    light mode: start on connect, stop on sleep/wake if no device;
#                           nothing ever stays running
#   ./install.sh --polling  fallback: check every $INTERVAL seconds with a shell script
# Event and light modes need swiftc (Xcode Command Line Tools).
set -eu

PREFIX="${PREFIX:-$HOME/.local}"
INTERVAL="${INTERVAL:-20}"
LABEL="io.github.logi-ondemand"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE=event

case "${1:-}" in
  --polling) MODE=polling;;
  --light)   MODE=light;;
  "")        ;;
  *) echo "usage: ./install.sh [--light | --polling]" >&2; exit 1;;
esac
if [ "$(uname)" != Darwin ]; then echo "macOS only." >&2; exit 1; fi

if [ "$MODE" != polling ] && ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found — falling back to polling mode."
  echo "(Install Xcode Command Line Tools with 'xcode-select --install' and re-run for event mode.)"
  MODE=polling
fi

mkdir -p "$PREFIX/bin" "$HOME/Library/LaunchAgents"
install -m 755 "$SRC_DIR/bin/logi" "$PREFIX/bin/logi"
echo "installed $PREFIX/bin/logi"

if [ "$MODE" != polling ]; then
  if [ "$MODE" = light ]; then
    EXTRA_ARG="<string>--oneshot</string>"
    POWER_EVENT="
    <key>com.apple.notifyd.matching</key>
    <dict>
      <key>sleep-wake</key>
      <dict><key>Notification</key><string>com.apple.powermanagement.systempowerstate</string></dict>
    </dict>"
  else
    EXTRA_ARG=""; POWER_EVENT=""
  fi
  echo "building logi-watch..."
  swiftc -O "$SRC_DIR/src/logi-watch.swift" -o "$PREFIX/bin/logi-watch"
  echo "installed $PREFIX/bin/logi-watch"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$PREFIX/bin/logi-watch</string>$EXTRA_ARG</array>
  <key>RunAtLoad</key><true/>
  <key>LaunchEvents</key>
  <dict>
    <key>com.apple.iokit.matching</key>
    <dict>
      <key>logitech-hid</key>
      <dict>
        <key>IOProviderClass</key><string>IOHIDDevice</string>
        <key>VendorID</key><integer>1133</integer>
        <key>PrimaryUsagePage</key><integer>1</integer>
        <key>IOMatchLaunchStream</key><true/>
      </dict>
    </dict>$POWER_EVENT
  </dict>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict>
</plist>
EOF
else
  rm -f "$PREFIX/bin/logi-watch"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$PREFIX/bin/logi</string><string>check</string></array>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict>
</plist>
EOF
fi

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
if [ "$MODE" = event ]; then
  echo "watcher loaded (event mode: wakes only when a Logitech device connects)"
elif [ "$MODE" = light ]; then
  echo "watcher loaded (light mode: runs only on device connect and sleep/wake, then exits)"
else
  echo "watcher loaded (polling mode: checks every ${INTERVAL}s)"
fi

case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *) echo
     echo "note: $PREFIX/bin is not on your PATH. Add this to ~/.zshrc:"
     echo "  export PATH=\"$PREFIX/bin:\$PATH\"";;
esac

echo
"$PREFIX/bin/logi" status
