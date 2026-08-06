#!/bin/bash
# Cuts a release: builds the app, zips it, signs the zip with the Sparkle EdDSA key,
# regenerates the appcast, and pushes everything so installed copies see the update.
#
# Usage: ./release.sh 1.1.0
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:?사용법: ./release.sh 1.1.0}"
REPO="howiknow/catwalk"
PREFIX="https://raw.githubusercontent.com/$REPO/main/releases/"
TOOLS=".build/artifacts/sparkle/Sparkle/bin"

if [ ! -x "$TOOLS/generate_appcast" ]; then
    echo "Sparkle 도구가 없습니다. 먼저 'swift build -c release' 를 실행하세요." >&2
    exit 1
fi

echo "$VERSION" > VERSION
./build.sh "$VERSION"

mkdir -p releases
# ASCII only: GitHub serves Korean paths in NFC while macOS stores NFD,
# which made the appcast download URL 404.
ZIP="releases/YenaCat-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent dist/예나캣.app "$ZIP"

# Signs every zip in the folder with the key from the keychain and rewrites appcast.xml.
"$TOOLS/generate_appcast" --download-url-prefix "$PREFIX" releases/

git add -A
git commit -m "Release $VERSION" || echo "커밋할 변경 없음"
git push

if gh release view "v$VERSION" >/dev/null 2>&1; then
    gh release upload "v$VERSION" "$ZIP" --clobber
else
    gh release create "v$VERSION" "$ZIP" \
        --title "CatWalk $VERSION" \
        --notes "CatWalk $VERSION — 설치 방법은 README를 참고하세요."
fi

echo
echo "릴리스 완료: $VERSION"
echo "  appcast: ${PREFIX}appcast.xml"
echo "  다운로드: https://github.com/$REPO/releases/tag/v$VERSION"
