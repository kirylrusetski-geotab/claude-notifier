#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/claude-notifier.app"
BIN_DIR="$APP_DIR/Contents/MacOS"

echo "Compiling claude-notifier…"
swiftc \
    "$SCRIPT_DIR/claude-notifier.swift" \
    "$SCRIPT_DIR/claude-notifier-config.swift" \
    "$SCRIPT_DIR/claude-notifier-settings.swift" \
    "$SCRIPT_DIR/claude-notifier-onboarding.swift" \
    -framework Cocoa \
    -framework UserNotifications \
    -framework SwiftUI \
    -o "$BIN_DIR/claude-notifier"

echo "Signing…"
codesign --force --deep --sign - "$APP_DIR"

echo "Done. Binary: $BIN_DIR/claude-notifier"
