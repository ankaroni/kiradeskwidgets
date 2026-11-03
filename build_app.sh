#!/bin/bash
# HavaliWidget.app paketini oluşturur
set -e
cd "$(dirname "$0")"
swift build -c release
APP=HavaliWidget.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/HavaliWidget "$APP/Contents/MacOS/HavaliWidget"
ICONSET=.build/AppIcon.iconset
rm -rf "$ICONSET"
swift tools/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>HavaliWidget</string>
<key>CFBundleDisplayName</key><string>HavaliWidget</string>
<key>CFBundleIdentifier</key><string>local.havaliwidget.app</string>
<key>CFBundleExecutable</key><string>HavaliWidget</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1.0</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Müzik çalar widget'ı Spotify ve Müzik'te çalan parçayı okumak ve kontrol etmek için.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>Ajanda widget'ı yaklaşan etkinliklerinizi göstermek için.</string>
<key>NSCalendarsUsageDescription</key><string>Ajanda widget'ı yaklaşan etkinliklerinizi göstermek için.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
xattr -cr "$APP"   # Finder öznitelikleri imzayı engeller
# İzinlerin (Takvim, Otomasyon) yeniden derlemede kaybolmaması için imza gereksinimini
# değişen parmak izi yerine sabit uygulama kimliğine bağla.
codesign --force --sign - -r='designated => identifier "local.havaliwidget.app"' "$APP"
echo "Hazır: $PWD/$APP"
