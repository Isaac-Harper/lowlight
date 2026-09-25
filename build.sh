#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/Lowlight.app"
BIN_NAME="Lowlight"
BUNDLE_ID="dev.isaacharper.lowlight"
IDENTITY="${LOWLIGHT_SIGN_IDENTITY:-}"

echo "==> Building (release)"
cd "$ROOT"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$BIN_NAME"

echo "==> Assembling $APP"
pkill -x "$BIN_NAME" || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN" "$APP/Contents/MacOS/$BIN_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Lowlight</string>
    <key>CFBundleDisplayName</key><string>Lowlight</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$BIN_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

cat > "$APP/Contents/Library/LaunchAgents/$BUNDLE_ID.plist" <<AGENTPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$BUNDLE_ID</string>
    <key>BundleProgram</key><string>Contents/MacOS/$BIN_NAME</string>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key><false/>
    </dict>
    <key>ProcessType</key><string>Interactive</string>
    <key>ThrottleInterval</key><integer>5</integer>
</dict>
</plist>
AGENTPLIST

if [ -n "$IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "==> Signing with $IDENTITY"
    SIGN_AS="$IDENTITY"
else
    echo "==> Signing ad-hoc"
    SIGN_AS="-"
fi
codesign --force --options runtime --timestamp=none --sign "$SIGN_AS" "$APP"
codesign --verify --strict "$APP"

echo "==> Done: $APP"
if launchctl print "gui/$(id -u)/$BUNDLE_ID" >/dev/null 2>&1; then
    launchctl kickstart "gui/$(id -u)/$BUNDLE_ID" && echo "    Restarted the login agent"
fi
