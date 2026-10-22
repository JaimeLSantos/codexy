#!/bin/zsh
# Makes dist/Codexy-<version>-macos.zip: a universal (Apple silicon + Intel) app, ad-hoc signed, with its SHA-256.
# There is no Developer ID here, so the download is NOT notarized: macOS asks the user to allow it (see the README).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(tr -d "[:space:]" < VERSION)
# Built outside Documents (its file provider adds attributes that break codesign), copied into dist/ only as a zip.
STAGE=$HOME/Library/Caches/codexy-build/dist
APP="$STAGE/Codexy.app"
mkdir -p dist
ARCHS="arm64 x86_64" APP="$APP" ./scripts/bundle.sh
ZIP="dist/Codexy-$VERSION-macos.zip"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent --norsrc "$APP" "$ZIP"
(cd dist && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
echo "built $ZIP"; cat "$ZIP.sha256"
lipo -archs "$APP/Contents/MacOS/CodexyUsage"
