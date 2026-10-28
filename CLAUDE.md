# MouseBetter

BetterAndBetter 를 대체하는 macOS 메뉴바 상주 앱. 우클릭 드래그 제스처와 창 스냅 단축키를 제공한다.
작업 기록 문서: https://claude.ai/artifact/6kDGKfqLueXbVxAdFaAe4Q

## 빌드·실행

- Xcode 없이 Command Line Tools(Swift 6.4) + SwiftPM 으로 빌드한다. Package.swift 는 tools 5.9(언어 모드 5).
- `scripts/build.sh` → `build/MouseBetter.app` 생성 (ad-hoc 서명)
- `scripts/build.sh install` → `~/Applications` 설치, 손쉬운 사용 권한 초기화 후 실행
- `scripts/build.sh test` → GestureCore 단위 테스트 (swift-testing)
  - CLT 환경에서는 `-plugin-path .../host/plugins/testing` 이 없으면 `@Test` 매크로를 못 찾는다. 스크립트가 처리한다.

## 구조

- `Sources/GestureCore` : 궤적 → 방향열 → Gesture 매핑. AppKit 의존 없음, 테스트 대상.
- `Sources/MouseBetter/MouseGestureTap.swift` : CGEventTap 으로 우클릭 down/drag/up 처리. 움직임 없으면 클릭 재전송.
- `TrailOverlay.swift` : 모니터별 투명 창에 CAShapeLayer 로 궤적 표시.
- `Actions.swift` : 탭 닫기·리로드는 AX 로 창 포커스 후 ⌘W/⌘R 전송, 스크롤은 픽셀 휠 이벤트.
- `AppHistory.swift` : 앱 활성화 순서 기록, ㄱ 제스처로 직전 앱 활성화 (⌘Tab 대체).
- `WindowSnapper.swift` + `HotKeyCenter.swift` : Carbon 핫키(⌃⌥⌘ + 방향키/P/M/F//) → AX 로 창 위치·크기·전체 화면 설정.

## 제스처·단축키 추가 방법

- 제스처: `GestureCore` 의 `Gesture.bindings` 에 한 줄 + `Gesture.title` + `Actions.perform` 에 동작.
- 단축키: `WindowSnapper.bindings` 에 한 줄 + `Command.title` + `perform` 분기.
- 메뉴바 기능 목록은 두 매핑 표에서 자동 생성된다.

## 주의 사항

- 좌표계: CGEvent·AX·CGWindowList 는 Quartz(좌상단 원점), NSScreen·NSWindow 는 Cocoa(좌하단 원점). 변환은 `ScreenGeometry`.
- ad-hoc 서명은 빌드마다 서명 해시가 바뀌어 손쉬운 사용 권한이 무효가 된다. 재빌드 후에는 `install` 로 권한을 다시 받는다.
- 재전송 이벤트는 `eventSourceUserData = 0x4D424554` 로 표시해 탭이 다시 가로채지 않게 한다.
