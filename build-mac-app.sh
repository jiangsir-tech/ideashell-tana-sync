#!/bin/zsh
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="闪念同步"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_DISPLAY_VERSION="${APP_DISPLAY_VERSION:-$APP_VERSION}"
APP_BUILD="${APP_BUILD:-1}"
APP_DIR="$BASE_DIR/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

if [[ -f "$BASE_DIR/AppIcon/AppIcon-source.png" ]]; then
  "$BASE_DIR/generate-app-icon.sh"
fi

for arch in arm64 x86_64; do
  /usr/bin/swiftc \
    -parse-as-library \
    -target "$arch-apple-macosx14.0" \
    -framework SwiftUI \
    -framework Charts \
    -framework AppKit \
    -framework ServiceManagement \
    "$BASE_DIR/MacApp/NativeSync.swift" \
    "$BASE_DIR/MacApp/UpdateChecker.swift" \
    "$BASE_DIR/MacApp/IdeaShellTanaApp.swift" \
    -o "$MACOS/IdeaShellTana-$arch"
done
lipo -create "$MACOS/IdeaShellTana-arm64" "$MACOS/IdeaShellTana-x86_64" -output "$MACOS/IdeaShellTana"
rm "$MACOS/IdeaShellTana-arm64" "$MACOS/IdeaShellTana-x86_64"

cp "$BASE_DIR/polish-prompt.md" "$BASE_DIR/polish-prompt.en.md" "$RESOURCES/"
if [[ -d "$BASE_DIR/Localization" ]]; then
  ditto "$BASE_DIR/Localization" "$RESOURCES"
fi
if [[ -f "$BASE_DIR/AppIcon/AppIcon.icns" ]]; then
  cp "$BASE_DIR/AppIcon/AppIcon.icns" "$RESOURCES/"
fi

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
  <key>CFBundleExecutable</key><string>IdeaShellTana</string>
  <key>CFBundleIdentifier</key><string>com.ideashell.tana-sync</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>闪念同步</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$APP_BUILD</string>
  <key>IdeaSyncDisplayVersion</key><string>$APP_DISPLAY_VERSION</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 江sir爱数码 · MIT License</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

plutil -lint "$CONTENTS/Info.plist"
echo "Built: $APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
  INSTALL_DIR="$HOME/Applications/$APP_NAME.app"
  mkdir -p "$HOME/Applications"
  ditto "$APP_DIR" "$INSTALL_DIR"
  echo "Installed: $INSTALL_DIR"
fi
