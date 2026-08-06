# 예나캣 (CatWalk)

고양이가 화면을 돌아다니는 macOS 데스크톱 펫. 메뉴바에서 동작하고 Dock 아이콘은 없습니다.

![고양이](https://img.shields.io/badge/macOS-13%2B-black)

## 설치

1. [최신 릴리스](https://github.com/howiknow/catwalk/releases/latest)에서 `예나캣-x.y.z.zip` 을 받습니다.
2. 압축을 풀고 `예나캣.app` 을 **응용 프로그램** 폴더로 옮깁니다.
3. 처음 열 때 "확인되지 않은 개발자" 경고가 뜹니다. Apple 유료 개발자 계정으로 공증(notarize)하지 않아서 그렇습니다.
   **시스템 설정 → 개인정보 보호 및 보안** 으로 가서 아래쪽의 `"예나캣"을(를) 열도록 허용` 을 누르면 됩니다. 이 과정은 처음 한 번만 필요합니다.

설치되면 메뉴바에 🐱 아이콘이 생깁니다.

## 사용법

| 동작 | 방법 |
| --- | --- |
| 자리에 고정 | 고양이를 원하는 곳으로 **드래그** |
| 고정 해제 | 고양이 **더블클릭** (또는 메뉴 → 고정 전부 풀기) |
| 사진 넘기기 | 고양이에 마우스를 올리고 **‹ ›** 클릭 |
| 크기 조절 | 마우스를 올리고 **우측 하단 핸들** 드래그 |
| 사진 교체·삭제 | 고양이 **우클릭** |
| 고양이 추가 | 메뉴바 🐱 → 고양이 추가 |

고양이는 화면 바닥을 걷고, 창 위에 올라타고, 화면 가장자리를 타고 올라가 천장에 매달립니다. 가만히 두면 잠들기도 하고, 가끔 말풍선으로 한마디씩 겁니다.

## 내 사진 넣기

메뉴바 🐱 → **GIF 폴더 열기** 를 누르면 열리는 폴더에 `.gif` 나 `.png` 를 넣으면 바로 고양이로 쓰입니다. 앱을 다시 켤 필요 없습니다.

```
~/Library/Application Support/CatWalk/cats
```

배경이 투명한 이미지를 넣으면 네모 없이 모양 그대로 돌아다닙니다. 기본으로 들어있는 고양이들은 macOS Vision 으로 배경을 지워둔 것입니다 — 직접 받은 사진도 아래 한 줄로 같은 처리를 할 수 있습니다.

```bash
swift Tools/RemoveBackground.swift ~/Library/Application\ Support/CatWalk/cats /tmp/cut
cp /tmp/cut/*.png ~/Library/Application\ Support/CatWalk/cats/
```
 기본 고양이는 [TheCatAPI](https://thecatapi.com) 에서 받아옵니다.

## 업데이트

새 버전이 나오면 앱이 스스로 알려주고 설치합니다([Sparkle](https://sparkle-project.org) 사용). 직접 확인하려면 메뉴바 🐱 → **업데이트 확인…**.

## 직접 빌드하기

```bash
git clone https://github.com/howiknow/catwalk.git
cd catwalk
./build.sh
open dist/예나캣.app
```

Swift 5.9+ 와 macOS 13+ 가 필요합니다.

### 릴리스 내기 (관리자용)

```bash
./release.sh 1.1.0
```

빌드 → zip → EdDSA 서명 → appcast 갱신 → 푸시 → GitHub 릴리스 생성까지 한 번에 합니다.
서명용 개인키는 키체인의 `Private key for signing Sparkle updates` 항목에 있습니다. **이 키를 잃어버리면 기존 사용자에게 업데이트를 내보낼 수 없으니 반드시 백업하세요.**
