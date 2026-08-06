# 예나캣 (CatWalk)

고양이가 화면을 돌아다니는 macOS 데스크톱 펫. 메뉴바에서 동작하고 Dock 아이콘은 없습니다.

![고양이](https://img.shields.io/badge/macOS-13%2B-black)

## 설치

1. [최신 릴리스](https://github.com/howiknow/catwalk/releases/latest)에서 `YenaCat-x.y.z.zip` 을 받습니다.
2. 압축을 풀고 `예나캣.app` 을 **응용 프로그램** 폴더로 옮깁니다. (반드시 옮긴 뒤에 여세요)
3. 앱을 더블클릭하면 이런 경고가 뜨고 열리지 않습니다:

   > **'예나캣'을(를) 열지 않음**
   > Apple은 '예나캣'에 사용자의 Mac에 손상을 입히거나 사용자의 개인정보에 침입할 수 있는 악성 코드가 없음을 확인할 수 없습니다.

   바이러스가 있다는 뜻이 아니라, 유료 Apple 개발자 계정으로 **공증(notarize)** 을 받지 않은 앱이라 macOS 가 일단 막는 것입니다.

4. `완료` 를 눌러 창을 닫고 **시스템 설정 → 개인정보 보호 및 보안** 을 엽니다.
5. 아래로 스크롤하면 `"예나캣"이(가) 차단되었습니다` 라는 줄과 **[그래도 열기]** 버튼이 있습니다. 그걸 누르고, 물어보면 암호나 Touch ID 로 확인합니다.
6. 다시 앱을 엽니다. 이 과정은 **처음 한 번만** 필요합니다.

> **[그래도 열기] 버튼이 안 보이나요?** 4~5 단계는 3번에서 한 번 열기를 시도한 뒤에야 나타납니다. 그래도 없으면 터미널에서 아래 한 줄을 실행하고 다시 열어보세요.
>
> ```bash
> xattr -cr /Applications/예나캣.app
> ```

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
