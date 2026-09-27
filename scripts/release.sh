#!/bin/zsh
# Builds a self-contained Muon.app (tool server bundled) and zips it for a GitHub release.
# Usage: scripts/release.sh 0.1.0
set -e
VERSION=${1:?usage: scripts/release.sh <version>}
cd "$(dirname "$0")/.."
ROOT=$PWD
OUT=build/release; rm -rf "$OUT"; mkdir -p "$OUT"

echo "▸ tool server"
(cd mac-tools && npm install --silent && npm run build --silent && node --test "test/*.test.mjs" >/dev/null)
STAGE="$OUT/mac-tools"; mkdir -p "$STAGE"
cp -R mac-tools/dist "$STAGE/dist"; cp mac-tools/package.json "$STAGE/"
(cd "$STAGE" && npm install --omit=dev --silent --no-audit --no-fund)

echo "▸ app (Release)"
sed -i '' "s/CFBundleShortVersionString: \".*\"/CFBundleShortVersionString: \"$VERSION\"/" project.yml
xcodegen generate --quiet
xcodebuild -project Muon.xcodeproj -scheme Muon -configuration Release -derivedDataPath "$OUT/DerivedData" build >"$OUT/xcodebuild.log" 2>&1 \
  || { tail -20 "$OUT/xcodebuild.log"; exit 1; }
APP="$OUT/DerivedData/Build/Products/Release/Muon.app"

echo "▸ bundle tool server into the app and re-sign"
rm -rf "$APP/Contents/Resources/mac-tools"
cp -R "$STAGE" "$APP/Contents/Resources/mac-tools"
codesign --force --deep --options runtime --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "▸ zip"
ZIP="$OUT/Muon-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$OUT/Muon-$VERSION.zip.sha256"
du -h "$ZIP" | cut -f1 | xargs echo "size:"
echo "done: $ZIP"
