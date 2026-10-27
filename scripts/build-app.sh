#!/bin/zsh
# Compila e empacota NotchCRTV.app em ./build. Uso: scripts/build-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/NotchCRTV.app
VERSION=1.0.0

swift run -c release SelfTest | tail -1
swift build -c release --product NotchCRTV

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchCRTV "$APP/Contents/MacOS/NotchCRTV"
strip -S "$APP/Contents/MacOS/NotchCRTV"

ICONSET=build/NotchCRTV.iconset
swift scripts/make-icon.swift build/icon.png
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>NotchCRTV</string>
  <key>CFBundleDisplayName</key><string>NotchCRTV</string>
  <key>CFBundleIdentifier</key><string>com.lipenoe.notchcrtv</string>
  <key>CFBundleExecutable</key><string>NotchCRTV</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key><string>Para ditar demandas por voz.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Para transformar sua fala em demanda.</string>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Nova demanda no NotchCRTV</string></dict>
      <key>NSMessage</key><string>createTask</string>
      <key>NSPortName</key><string>NotchCRTV</string>
      <key>NSRequiredContext</key><dict/>
      <key>NSSendTypes</key><array><string>NSStringPboardType</string><string>public.utf8-plain-text</string><string>public.url</string></array>
      <key>NSSendFileTypes</key><array><string>public.item</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

codesign --force --sign - "$APP"
echo "OK: $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x NotchCRTV || true
  rm -rf /Applications/NotchCRTV.app
  cp -R "$APP" /Applications/
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/NotchCRTV.app
  /System/Library/CoreServices/pbs -update 2>/dev/null || true
  echo "Instalado em /Applications/NotchCRTV.app"
fi
