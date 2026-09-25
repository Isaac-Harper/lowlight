#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: ./release.sh <version>, e.g. ./release.sh 0.1.0}"
PROFILE="${LOWLIGHT_NOTARY_PROFILE:-lowlight-notary}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/Lowlight.app"
ZIP="$ROOT/dist/Lowlight-$VERSION.zip"
cd "$ROOT"

IDENTITY="$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
[ -n "$IDENTITY" ] || { echo "No Developer ID Application certificate in the keychain."; exit 1; }
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || { echo "No notary credentials saved as '$PROFILE'. Run: xcrun notarytool store-credentials $PROFILE"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash changes first."; exit 1; }
! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || { echo "Tag v$VERSION already exists."; exit 1; }

LOWLIGHT_SIGN_IDENTITY="$IDENTITY" LOWLIGHT_VERSION="$VERSION" ./build.sh

echo "==> Notarizing"
mkdir -p dist
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl -a -vv "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Publishing v$VERSION"
git tag "v$VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" "$ZIP" --title "Lowlight $VERSION" --generate-notes
