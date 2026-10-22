#!/bin/zsh
# Regenerates Resources/AppIcon.icns from the Theo drawing in Snapshot.swift (IconView).
set -euo pipefail
cd "$(dirname "$0")/.."
S=$HOME/Library/Caches/codexy-build
swift build --scratch-path "$S" >/dev/null
OUT=$(mktemp -d)
"$S/debug/CodexyUsage" --icon "$OUT"
mkdir -p Resources
iconutil -c icns "$OUT/AppIcon.iconset" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns"
