#!/bin/zsh
# Regenerate the Xcode project and build Debug. Usage: scripts/build.sh [test]
set -e
cd "$(dirname "$0")/.."
xcodegen generate --quiet
LOG=build/xcodebuild.log; mkdir -p build
if [[ "$1" == "test" ]]; then
  xcodebuild -project MacAgent.xcodeproj -scheme MacAgent -configuration Debug -derivedDataPath build/DerivedData test >"$LOG" 2>&1 || true
  grep -E "error:|Test Suite .* (passed|failed)|Executed|TEST (SUCCEEDED|FAILED)|\*\* " "$LOG" | tail -30
else
  xcodebuild -project MacAgent.xcodeproj -scheme MacAgent -configuration Debug -derivedDataPath build/DerivedData build >"$LOG" 2>&1 || true
  grep -E "error:|warning: unre|BUILD (SUCCEEDED|FAILED)" "$LOG" | sort -u | tail -30
fi
