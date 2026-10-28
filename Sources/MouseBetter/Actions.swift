import AppKit
import Carbon.HIToolbox
import GestureCore

/// 제스처에 대응하는 동작을 실행한다.
///
/// - 탭 닫기, 리로드: 앱마다 탭 구조가 달라 AX 로는 공통 처리가 불가능하므로 단축키를 보낸다.
///   다만 우클릭을 삼켰기 때문에 제스처를 그린 창이 포커스를 받지 못한다. 그래서 먼저 AX 로
///   그 창을 앞으로 가져온 다음 키를 보낸다.
/// - 스크롤: 키보드 포커스와 무관하게 커서 아래 뷰가 반응하도록 스크롤 휠 이벤트를 보낸다.
@MainActor
enum Actions {
    static func perform(_ gesture: Gesture, startedAt point: CGPoint) {
        switch gesture {
        case .closeTab:
            focusWindow(at: point) { sendKey(CGKeyCode(kVK_ANSI_W), flags: .maskCommand) }
        case .reload:
            focusWindow(at: point) { sendKey(CGKeyCode(kVK_ANSI_R), flags: .maskCommand) }
        case .previousApp:
            AppHistory.shared.activatePrevious()
        case .scrollToBottom:
            scrollToEnd(down: true)
        case .scrollToTop:
            scrollToEnd(down: false)
        }
    }

    // MARK: - 창 포커스

    /// point 아래에 있는 일반 창을 찾아 그 앱을 활성화하고 창을 맨 앞으로 올린 뒤 then 을 실행한다.
    private static func focusWindow(at point: CGPoint, then action: @escaping @MainActor @Sendable () -> Void) {
        guard let target = topWindow(at: point) else { action(); return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let axApp = AXUIElementCreateApplication(target.pid)
        let focused = AX.element(axApp, kAXFocusedWindowAttribute)
        let alreadyFocused = frontmost == target.pid && focused.flatMap(AX.frame(of:)) == target.bounds
        if alreadyFocused { action(); return }

        if let window = AX.elements(axApp, kAXWindowsAttribute).first(where: { AX.frame(of: $0) == target.bounds }) {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        AX.activate(pid: target.pid)
        // 활성화가 반영될 시간을 준 뒤 키를 보낸다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: action)
    }

    /// 창 목록은 앞에서 뒤 순서로 정렬되어 있다. 자기 자신(궤적 오버레이)과 메뉴바·Dock 등은 제외한다.
    private static func topWindow(at point: CGPoint) -> (pid: pid_t, bounds: CGRect)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        let me = getpid()
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let boundsDict = info[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary),
                  bounds.contains(point)
            else { continue }
            return (pid, bounds)
        }
        return nil
    }

    // MARK: - 입력 합성

    private static func sendKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// 픽셀 단위 스크롤 이벤트를 크게 여러 번 보내 끝까지 이동시킨다.
    /// 양수는 문서의 위쪽, 음수는 아래쪽 방향이다.
    private static func scrollToEnd(down: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let delta: Int32 = down ? -50_000 : 50_000
        for _ in 0..<8 {
            let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1,
                                wheel1: delta, wheel2: 0, wheel3: 0)
            event?.post(tap: .cghidEventTap)
        }
    }
}
