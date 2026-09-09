#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/O-Train Timer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/OTrainTimer" "$APP/Contents/MacOS/OTrainTimer"
swift scripts/generate-icon.swift "$PWD/dist/AppIcon.iconset"
iconutil -c icns "$PWD/dist/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>OTrainTimer</string>
<key>CFBundleIdentifier</key><string>ca.local.otrain-timer</string>
<key>CFBundleName</key><string>O-Train Timer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf '\nBuilt: %s\nRun: open "%s"\n' "$APP" "$APP"
