#!/usr/bin/env bash
#
# Builds MacTools, signs it, installs it into ~/Applications, and relaunches it.
# Usage:
#   ./install.sh            build + install to ~/Applications + relaunch the installed app
#   ./install.sh --no-launch   build + install only (don't quit/relaunch)
#
set -euo pipefail

APP_NAME="MacTools"
BUNDLE="${APP_NAME}.app"
BUILD_CONFIG="release"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$BUNDLE"

# Flags
LAUNCH=true
for arg in "$@"; do
    case "$arg" in
        --no-launch) LAUNCH=false ;;
        *) echo "Unknown option: $arg" >&2; echo "Usage: $0 [--no-launch]" >&2; exit 1 ;;
    esac
done

cd "$(dirname "$0")"

echo "==> Building ($BUILD_CONFIG)..."
swift build -c "$BUILD_CONFIG"

BIN_PATH="$(swift build -c "$BUILD_CONFIG" --show-bin-path)/$APP_NAME"

echo "==> Assembling $BUNDLE..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>mac-tools</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.getoutreach.mac-tools</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Code signing..."
SIGN_IDENTITY="mac-tools-signing"
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "    Using stable identity '$SIGN_IDENTITY' (Accessibility grant will persist)."
    codesign --force --deep --sign "$SIGN_IDENTITY" "$BUNDLE"
else
    echo "    No '$SIGN_IDENTITY' identity found — using ad-hoc (macOS will re-ask for"
    echo "    Accessibility on every rebuild). Run ./setup-signing.sh once to fix this."
    codesign --force --deep --sign - "$BUNDLE"
fi

# ---- Quit the running app before replacing the installed bundle ----
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "==> '$APP_NAME' is running — quitting it before install..."
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
        sleep 0.2
    done
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "    Still running — forcing kill."
        pkill -x "$APP_NAME" || true
        sleep 0.3
    fi
fi

# ---- Install into ~/Applications ----
echo "==> Installing to $INSTALLED_APP ..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
cp -R "$BUNDLE" "$INSTALLED_APP"

echo "==> Done: $INSTALLED_APP"

if [ "$LAUNCH" = true ]; then
    echo "==> Launching installed app..."
    open "$INSTALLED_APP"
else
    echo "    Launch it with:  open \"$INSTALLED_APP\""
fi
