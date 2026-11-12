#!/usr/bin/env bash
# Builds a release of flyt, zips it, signs the zip with Sparkle's EdDSA key and
# adds it to docs/appcast.xml. See RELEASING.md.
#
#   scripts/release.sh VERSION [BUILD]
#
# VERSION is the marketing version (e.g. 0.6.0). BUILD is the build number
# Sparkle compares to decide what's newer; it must be higher than every build
# already in the appcast and defaults to one more than the highest of them.
#
# Run it on an up-to-date, clean `main`: that's the branch GitHub Pages
# serves the appcast from, so the appcast commit has to land there. Set
# RELEASE_SKIP_GIT_CHECKS=1 to try the script out elsewhere.
#
# Needs Sparkle's command-line tools. Set SPARKLE_BIN to the folder holding
# `sign_update` (downloaded from Sparkle's releases page), or build the app
# once in Xcode and it's found under DerivedData.
set -euo pipefail

if [[ $# -lt 1 ]]; then
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

VERSION="$1"
REPO="ctenhove/flyt"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST="$ROOT/docs/appcast.xml"
APPCAST_TOOL="$ROOT/scripts/add_appcast_item.py"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/flyt.xcarchive"
ZIP="$OUT/flyt-$VERSION.zip"

fail() { echo "error: $*" >&2; exit 1; }

find_sparkle_bin() {
    if [[ -n "${SPARKLE_BIN:-}" ]]; then echo "$SPARKLE_BIN"; return; fi
    local found
    found="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/flyt-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -n 1 || true)"
    if [[ -n "$found" ]]; then echo "$found"; return; fi
    fail "can't find Sparkle's tools; set SPARKLE_BIN to the folder containing sign_update"
}
SPARKLE_BIN="$(find_sparkle_bin)"

if [[ -z "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/Resources/Info.plist" 2>/dev/null)" ]]; then
    fail "SUPublicEDKey is empty in Resources/Info.plist — generate a key first (see RELEASING.md)"
fi

if [[ -z "${RELEASE_SKIP_GIT_CHECKS:-}" ]]; then
    [[ "$(git -C "$ROOT" branch --show-current)" == "main" ]] \
        || fail "releases are cut from main, the branch GitHub Pages serves the appcast from"
    [[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]] \
        || fail "there are uncommitted changes; commit or stash them first"
    git -C "$ROOT" fetch --quiet origin main
    [[ "$(git -C "$ROOT" rev-parse HEAD)" == "$(git -C "$ROOT" rev-parse origin/main)" ]] \
        || fail "main isn't in step with origin/main; pull or push first"
fi

# Settled before the long build, not after it: a build or version the
# appcast already has would otherwise only be refused once a new zip exists,
# and that zip's signature wouldn't match the entry already published.
BUILD="${2:-$(python3 "$APPCAST_TOOL" "$APPCAST" --next-build)}"
python3 "$APPCAST_TOOL" "$APPCAST" --check --build "$BUILD" --version "$VERSION"

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
# What the app itself says it needs, so the appcast never offers an update
# to a Mac too old to launch it.
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
python3 "$APPCAST_TOOL" "$APPCAST" \
    --version "$VERSION" \
    --build "$BUILD" \
    --min-os "$MIN_OS" \
    --url "https://github.com/$REPO/releases/download/v$VERSION/flyt-$VERSION.zip" \
    --signature-line "$SIGNATURE_LINE" \
    --release-notes-url "https://github.com/$REPO/releases/tag/v$VERSION"

cat <<DONE

Done. To publish:
  1. gh release create v$VERSION "$ZIP" --title "flyt $VERSION" --generate-notes
  2. git add docs/appcast.xml && git commit -m "Appcast: $VERSION" && git push origin main
GitHub Pages then serves the new appcast, and installed copies offer the update.

To redo this release instead of publishing it, first drop the entry just added:
  git checkout docs/appcast.xml
DONE
