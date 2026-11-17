#!/bin/bash
# Installs `logi` and the background watcher (per-user, no sudo).
#
#   ./install.sh            event-driven watcher (needs swiftc / Xcode Command Line Tools)
#   ./install.sh --polling  fallback: check every $INTERVAL seconds with a shell script
set -eu

PREFIX="${PREFIX:-$HOME/.local}"
INTERVAL="${INTERVAL:-20}"
LABEL="io.github.logi-ondemand"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE=event

[ "${1:-}" = "--polling" ] && MODE=polling
if [ "$(uname)" != Darwin ]; then echo "macOS only." >&2; exit 1; fi

if [ "$MODE" = event ] && ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found — falling back to polling mode."
  echo "(Install Xcode Command Line Tools with 'xcode-select --install' and re-run for event mode.)"
  MODE=polling
fi

mkdir -p "$PREFIX/bin" "$HOME/Library/LaunchAgents"
install -m 755 "$SRC_DIR/bin/logi" "$PREFIX/bin/logi"
echo "installed $PREFIX/bin/logi"

if [ "$MODE" = event ]; then
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
  <array><string>$PREFIX/bin/logi-watch</string></array>
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
    </dict>
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
