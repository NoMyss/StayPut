#!/bin/bash
# Builds StayPut.app (Apple Silicon, macOS 13+). Needs Xcode or the Command Line Tools.
#
#   ./build.sh            Direct-download build (ad-hoc signed, not sandboxed).
#   ./build.sh appstore   Mac App Store build: sandboxed, no admin features.
#                         Signed ad-hoc for local testing, unless these are set:
#                           STORE_PROFILE=path/to/StayPut.provisionprofile
#                         Then it signs with "Apple Distribution" and writes build/StayPut.pkg
#                         (signed with "3rd Party Mac Developer Installer") for upload.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-direct}"
VERSION="1.0"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="app.stayput.StayPut"
TEAM_ID="JQ6J95ZC2J"

APP="build/StayPut.app"
rm -rf "$APP" build/StayPut.pkg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

FLAGS=()
[[ "$MODE" == "appstore" ]] && FLAGS+=(-D APPSTORE)

swiftc -O -swift-version 5 ${FLAGS[@]+"${FLAGS[@]}"} \
  -target arm64-apple-macos13.0 \
  -framework IOKit -framework AVFoundation -framework CoreAudio -framework Carbon \
  -framework LocalAuthentication -framework ServiceManagement \
  Sources/*.swift -o "$APP/Contents/MacOS/StayPut"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>StayPut</string>
  <key>CFBundleDisplayName</key><string>StayPut</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>StayPut</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Alex Maldonado</string>
</dict>
</plist>
PLIST

# App icon (drawn from an SF Symbol).
if swiftc -O tools/MakeIcon.swift -o build/makeicon 2>/dev/null; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    build/makeicon $s "$ICONSET/icon_${s}x${s}.png"
    build/makeicon $((s*2)) "$ICONSET/icon_${s}x${s}@2x.png"
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

xattr -cr "$APP"

if [[ "$MODE" != "appstore" ]]; then
  codesign --force --sign - "$APP"
  echo "Built $APP"
  exit 0
fi

ENT="build/StayPut.entitlements"
if [[ -n "${STORE_PROFILE:-}" ]]; then
  cp "$STORE_PROFILE" "$APP/Contents/embedded.provisionprofile"
  cat > "$ENT" <<ENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.device.usb</key><true/>
  <key>com.apple.application-identifier</key><string>$TEAM_ID.$BUNDLE_ID</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM_ID</string>
</dict>
</plist>
ENTS
  codesign --force --options runtime --timestamp --sign "Apple Distribution" --entitlements "$ENT" "$APP"
  productbuild --component "$APP" /Applications --sign "3rd Party Mac Developer Installer" build/StayPut.pkg
  echo "Built $APP and build/StayPut.pkg (ready to upload)"
else
  # Local test of the sandboxed build. The motion and lid sensors need the USB entitlement.
  cp StayPut.entitlements "$ENT"
  codesign --force --sign - --entitlements "$ENT" "$APP"
  echo "Built sandboxed $APP (ad-hoc signed, for local testing only)"
fi
