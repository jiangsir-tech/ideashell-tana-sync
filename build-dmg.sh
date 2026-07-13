#!/bin/zsh
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-0.1.0-beta.1}"
APP_NAME="闪念同步"
APP_PATH="$BASE_DIR/dist/$APP_NAME.app"
OUTPUT_PATH="$BASE_DIR/dist/$APP_NAME-$VERSION-unsigned.dmg"
STAGING_DIR="$(mktemp -d)"

if [[ -z "${APP_BUILD:-}" ]]; then
  if [[ "$VERSION" =~ 'beta\.([0-9]+)$' ]]; then
    APP_BUILD="${match[1]}"
  else
    echo "请通过 APP_BUILD 指定递增的构建号，例如：APP_BUILD=5 ./build-dmg.sh 0.1.0" >&2
    exit 1
  fi
fi

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

APP_VERSION="${APP_VERSION:-${VERSION%%-*}}" \
  APP_DISPLAY_VERSION="${APP_DISPLAY_VERSION:-$VERSION}" \
  APP_BUILD="$APP_BUILD" \
  "$BASE_DIR/build-mac-app.sh"
rm -f "$OUTPUT_PATH"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$BASE_DIR/INSTALL.md" "$STAGING_DIR/安装说明.md"

hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$OUTPUT_PATH"
hdiutil verify "$OUTPUT_PATH"
shasum -a 256 "$OUTPUT_PATH"
echo "Built: $OUTPUT_PATH"
