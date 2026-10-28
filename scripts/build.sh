#!/usr/bin/env bash
# 사용법:
#   scripts/build.sh            # build/MouseBetter.app 생성
#   scripts/build.sh install    # ~/Applications 에 설치 후 실행 (손쉬운 사용 권한 재요청)
#   scripts/build.sh test       # 제스처 인식기 단위 테스트
#   swift scripts/make-icon.swift  # 앱 아이콘(Resources/AppIcon.icns) 재생성
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.ica.mousebetter
APP=build/MouseBetter.app
# Command Line Tools 만 설치된 환경에서는 swift-testing 매크로 플러그인 경로를 직접 지정해야 한다
TESTING_PLUGIN=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

if [[ "${1:-}" == "test" ]]; then
  extra=()
  [[ -d "$TESTING_PLUGIN" ]] && extra=(-Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGIN")
  exec swift test "${extra[@]}"
fi

swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MouseBetter" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
echo "built: $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x MouseBetter || true
  # ad-hoc 서명은 빌드마다 서명 해시가 바뀌어 기존 권한이 무효가 된다. 항목을 지워 새로 요청받게 한다.
  tccutil reset Accessibility "$BUNDLE_ID" || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/MouseBetter.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/MouseBetter.app
  echo "installed: ~/Applications/MouseBetter.app"
fi
