import AppKit

/// Accessibility(AX) API 를 Swift 에서 쓰기 편하게 감싼 함수들.
/// AX 좌표계는 Quartz 와 같다 (원점: 주 모니터 좌상단, y 가 아래로 증가).
enum AX {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        (attribute(element, name) as? [AXUIElement]) ?? []
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(window, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    /// 백그라운드 앱의 NSRunningApplication.activate() 는 macOS 14 이후 무시될 수 있어 AX 로도 맨 앞으로 지정한다.
    static func activate(pid: pid_t) {
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        (attribute(window, "AXFullScreen") as? Bool) ?? false
    }

    static func setFullScreen(_ on: Bool, of window: AXUIElement) {
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
    }

    static func setFrame(_ frame: CGRect, of window: AXUIElement) {
        var origin = frame.origin
        var extent = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let size = AXValueCreate(.cgSize, &extent) else { return }
        // 모니터를 넘나들 때 크기 제약에 걸리지 않도록 크기 → 위치 → 크기 순서로 적용한다
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
    }
}

/// Cocoa(원점 좌하단) ↔ Quartz(원점 좌상단) 좌표 변환
enum ScreenGeometry {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func quartzRect(fromCocoa rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Quartz 좌표의 사각형 중심이 들어 있는 모니터
    static func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: primaryHeight - rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    /// 모니터를 왼쪽부터 오른쪽 순서로 돌아가며 다음 모니터를 고른다.
    static func screen(after screen: NSScreen) -> NSScreen? {
        let ordered = NSScreen.screens.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        guard ordered.count > 1, let index = ordered.firstIndex(of: screen) else { return nil }
        return ordered[(index + 1) % ordered.count]
    }
}
