#!/bin/bash
# Builds Tempo.app into ./build. Pass --install to copy it into /Applications and launch it.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Tempo.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Tempo "$APP/Contents/MacOS/Tempo"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
cp Resources/Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Tempo</string>
    <key>CFBundleDisplayName</key><string>Tempo</string>
    <key>CFBundleIdentifier</key><string>com.alexhughes.tempo</string>
    <key>CFBundleExecutable</key><string>Tempo</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Tempo reads the current tab's address so it can categorise the website you're on. Only the domain is stored, locally.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Tempo || true
    rm -rf /Applications/Tempo.app
    cp -R "$APP" /Applications/
    open /Applications/Tempo.app
    echo "Installed to /Applications/Tempo.app"
fi
