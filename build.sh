#!/bin/bash
# Baut Verbrauch.app (Intel + Apple Silicon) nach dist/, packt Verbrauch.zip
# und installiert die App nach /Applications.
set -e
cd "$(dirname "$0")"
VERSION="1.0"
APP="dist/Verbrauch.app"
rm -rf dist build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build

# Programm für beide Prozessorarten, ab macOS 13 (wegen Autostart über SMAppService)
swiftc -O -target arm64-apple-macos13  Verbrauch.swift -o build/Verbrauch-arm64
swiftc -O -target x86_64-apple-macos13 Verbrauch.swift -o build/Verbrauch-x86_64
lipo -create build/Verbrauch-arm64 build/Verbrauch-x86_64 -output "$APP/Contents/MacOS/Verbrauch"

# Symbol
swiftc icon.swift -o build/icon && build/icon build/icon.png
mkdir -p build/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Verbrauch</string>
<key>CFBundleDisplayName</key><string>Verbrauch</string>
<key>CFBundleIdentifier</key><string>de.openkairo.verbrauch</string>
<key>CFBundleExecutable</key><string>Verbrauch</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHumanReadableCopyright</key><string>SolarModule Gladbeck</string>
</dict></plist>
PL
codesign --force --deep -s - "$APP"
ditto -c -k --keepParent "$APP" dist/Verbrauch.zip

# Installieren: laufende Instanz beenden, nach /Applications kopieren, starten
pkill -x Verbrauch 2>/dev/null || true; sleep 1
rm -rf /Applications/Verbrauch.app && cp -R "$APP" /Applications/
open /Applications/Verbrauch.app
echo "Fertig: $(pwd)/dist/Verbrauch.zip  ·  installiert in /Applications"
