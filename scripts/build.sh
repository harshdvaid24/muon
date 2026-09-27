#!/bin/zsh
# Regenerate the Xcode project and build Debug. Usage: scripts/build.sh [test]
set -e
cd "$(dirname "$0")/.."
xcodegen generate --quiet
LOG=build/xcodebuild.log; mkdir -p build
if [[ "$1" == "test" ]]; then
  xcodebuild -project Muon.xcodeproj -scheme Muon -configuration Debug -derivedDataPath build/DerivedData test >"$LOG" 2>&1 || true
  grep -E "error:|✘|✔ (Suite|Test run)|TEST (SUCCEEDED|FAILED)" "$LOG" | grep -v "linkd\|Connection\]" | sed "s|$PWD/||" | tail -30
else
  xcodebuild -project Muon.xcodeproj -scheme Muon -configuration Debug -derivedDataPath build/DerivedData build >"$LOG" 2>&1 || true
  grep -E "error:|warning: unre|BUILD (SUCCEEDED|FAILED)" "$LOG" | sort -u | tail -30
fi
