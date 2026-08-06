#!/bin/bash
# Rebuilds the app icon from a source photo.
#
# Usage: ./make_icon.sh ~/Desktop/icon.png
set -euo pipefail

cd "$(dirname "$0")"
SOURCE="${1:?사용법: ./make_icon.sh <이미지 파일>}"

[ -f "$SOURCE" ] || { echo "파일이 없습니다: $SOURCE" >&2; exit 1; }

ICONSET="$(mktemp -d)/AppIcon.iconset"
swift Tools/MakeIcon.swift "$SOURCE" "$ICONSET"
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
rm -rf "$(dirname "$ICONSET")"

echo "생성 완료: Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1))"
echo "적용하려면 ./build.sh 를 다시 실행하세요."
