#!/usr/bin/env bash
# Builds "Krypton Transmute.app" from pure Krypton sources with kcc.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Krypton Transmute"
EXECUTABLE="KryptonTransmute"
BUNDLE_ID="com.krypton.transmute"
VERSION="1.0.0"

KCC="${KCC:-/usr/local/krypton/bootstrap/kcc_driver_macos_aarch64}"
if [ ! -x "$KCC" ]; then
  KCC="$(command -v kcc || true)"
fi
if [ -z "$KCC" ] || [ ! -x "$KCC" ]; then
  echo "error: kcc not found. Install Krypton or set KCC=/path/to/kcc" >&2
  exit 1
fi

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
MACOS_DIR="$APP/Contents/MacOS"
RESOURCES_DIR="$APP/Contents/Resources"

echo "==> Compiling Krypton sources with kcc"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
"$KCC" -o "$MACOS_DIR/$EXECUTABLE" "$ROOT/src/transmute.ks"
chmod +x "$MACOS_DIR/$EXECUTABLE"

if [ -f "$ROOT/assets/AppIcon.icns" ]; then
  cp "$ROOT/assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Image</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.image</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
if ! codesign --force --sign - "$APP" 2>/dev/null; then
  echo "    note: ad-hoc signing failed; the app may still launch"
fi

touch "$APP"
echo ""
echo "Built: $APP"
echo "Open it with: open \"$APP\""
