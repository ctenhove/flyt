#!/usr/bin/env bash
# Builds a release of flyt, zips it, signs the zip with Sparkle's EdDSA key and
# adds it to docs/appcast.xml. See RELEASING.md.
#
#   scripts/release.sh VERSION [BUILD]
#
# VERSION is the marketing version (e.g. 0.6.0). BUILD is the build number
# Sparkle compares to decide what's newer; it must increase with every
# release and defaults to the number of commits on this branch.
#
# Needs Sparkle's command-line tools. Set SPARKLE_BIN to the folder holding
# `sign_update` (downloaded from Sparkle's releases page), or build the app
# once in Xcode and it's found under DerivedData.
set -euo pipefail

if [[ $# -lt 1 ]]; then
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

VERSION="$1"
BUILD="${2:-$(git rev-list --count HEAD)}"
REPO="ctenhove/flyt"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/flyt.xcarchive"
ZIP="$OUT/flyt-$VERSION.zip"

find_sparkle_bin() {
    if [[ -n "${SPARKLE_BIN:-}" ]]; then echo "$SPARKLE_BIN"; return; fi
    local found
    found="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/flyt-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -n 1 || true)"
    if [[ -n "$found" ]]; then echo "$found"; return; fi
    echo "error: can't find Sparkle's tools; set SPARKLE_BIN to the folder containing sign_update" >&2
    exit 1
}
SPARKLE_BIN="$(find_sparkle_bin)"

if ! grep -q 'INFOPLIST_KEY_SUPublicEDKey = "[^"]\+"' "$ROOT/flyt.xcodeproj/project.pbxproj"; then
    echo "error: SUPublicEDKey is empty in the Xcode project — generate a key first (see RELEASING.md)" >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Building flyt $VERSION (build $BUILD)"
xcodebuild archive \
    -project "$ROOT/flyt.xcodeproj" \
    -scheme flyt \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    | tail -n 5

APP="$ARCHIVE/Products/Applications/flyt.app"
[[ -d "$APP" ]] || { echo "error: no app in the archive" >&2; exit 1; }

echo "==> Zipping"
# ditto, not zip: it keeps the code signature and symlinks inside the bundle intact.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Signing"
SIGNATURE_LINE="$("$SPARKLE_BIN/sign_update" "$ZIP")"

echo "==> Adding to docs/appcast.xml"
python3 "$ROOT/scripts/add_appcast_item.py" "$ROOT/docs/appcast.xml" \
    --version "$VERSION" \
    --build "$BUILD" \
    --url "https://github.com/$REPO/releases/download/v$VERSION/flyt-$VERSION.zip" \
    --signature-line "$SIGNATURE_LINE" \
    --release-notes-url "https://github.com/$REPO/releases/tag/v$VERSION"

cat <<DONE

Done. To publish:
  1. gh release create v$VERSION "$ZIP" --title "flyt $VERSION" --generate-notes
  2. git add docs/appcast.xml && git commit -m "Appcast: $VERSION" && git push
GitHub Pages then serves the new appcast, and installed copies offer the update.
DONE
