#!/bin/bash
# Builds CatWalk.app into ./dist
#
# Usage: ./build.sh [version]        e.g. ./build.sh 1.1.0
# The version is written into the bundle; Sparkle compares it against the appcast.
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-$(cat VERSION 2>/dev/null || echo 0.0.0)}"
APP="dist/CatWalk.app"
# Universal, so the app also runs on Intel Macs. This path is where SPM puts the
# merged binary when more than one --arch is given.
PRODUCTS=".build/apple/Products/Release"

swift build -c release --arch arm64 --arch x86_64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$PRODUCTS/CatWalk" "$APP/Contents/MacOS/CatWalk"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Sparkle ships as a framework with a helper app and XPC services inside it.
cp -R "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

# Sign inside out: nested code first, then the app itself.
codesign --force --options runtime --sign - \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" 2>/dev/null || true
codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"

echo "Built $APP  (version $VERSION)"
