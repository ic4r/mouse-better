import AppKit
import Carbon.HIToolbox

/// 맨 앞 앱의 포커스된 창을 AX 로 직접 옮기고 크기를 바꾼다.
@MainActor
enum WindowSnapper {
    enum Command {
        case leftHalf, rightHalf, topHalf, bottomHalf
        case nextScreen, toggleMaximize, toggleFullScreen, restoreOriginal

        var title: String {
            switch self {
            case .leftHalf: return "왼쪽 절반"
            case .rightHalf: return "오른쪽 절반"
            case .topHalf: return "위쪽 절반"
            case .bottomHalf: return "아래쪽 절반"
            case .nextScreen: return "다음 모니터로 이동"
            case .toggleMaximize: return "최대 크기 토글"
            case .toggleFullScreen: return "전체 화면 토글"
            case .restoreOriginal: return "처음 크기·위치로 복원"
            }
        }
    }

    static let modifierLabel = "⌃⌥⌘"

    /// 단축키 → 명령 매핑. 메뉴바의 기능 목록도 이 표로 만든다.
    static let bindings: [(keyCode: Int, keyLabel: String, command: Command)] = [
        (kVK_LeftArrow, "←", .leftHalf),
        (kVK_RightArrow, "→", .rightHalf),
        (kVK_UpArrow, "↑", .topHalf),
        (kVK_DownArrow, "↓", .bottomHalf),
        (kVK_ANSI_P, "P", .nextScreen),
        (kVK_ANSI_M, "M", .toggleMaximize),
        (kVK_ANSI_F, "F", .toggleFullScreen),
        (kVK_ANSI_Slash, "/", .restoreOriginal),
    ]

    /// AXUIElement 는 같은 창이면 CFEqual 이 참이므로 이를 딕셔너리 키로 쓴다.
    private struct WindowKey: Hashable {
        let element: AXUIElement
        static func == (lhs: WindowKey, rhs: WindowKey) -> Bool { CFEqual(lhs.element, rhs.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }

    private static var originalFrames: [WindowKey: CGRect] = [:]    // 처음 조작하기 전의 크기·위치
    private static var preMaximizeFrames: [WindowKey: CGRect] = [:] // 최대화 직전의 크기·위치

    static func registerHotKeys(on center: HotKeyCenter) {
        let modifiers = controlKey | optionKey | cmdKey
        for binding in bindings {
            let command = binding.command
            center.register(keyCode: binding.keyCode, modifiers: modifiers) { perform(command) }
        }
    }

    static func perform(_ command: Command) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = AX.element(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute)
        else { return }

        if command == .toggleFullScreen {
            AX.setFullScreen(!AX.isFullScreen(window), of: window)
            return
        }
        // 전체 화면 상태의 창은 위치와 크기를 바꿀 수 없다
        guard !AX.isFullScreen(window),
              let current = AX.frame(of: window),
              let screen = ScreenGeometry.screen(containing: current)
        else { return }

        let key = WindowKey(element: window)
        if command == .restoreOriginal {
            preMaximizeFrames[key] = nil
            if let original = originalFrames.removeValue(forKey: key) {
                AX.setFrame(original, of: window)
            }
            return
        }
        if originalFrames[key] == nil {
            originalFrames[key] = current
        }

        let area = ScreenGeometry.quartzRect(fromCocoa: screen.visibleFrame)
        let target: CGRect
        switch command {
        case .toggleMaximize:
            if let previous = preMaximizeFrames.removeValue(forKey: key) {
                target = previous
            } else {
                preMaximizeFrames[key] = current
                target = area
            }
        case .nextScreen:
            guard let next = ScreenGeometry.screen(after: screen) else { return }
            target = relocate(current, from: area, to: ScreenGeometry.quartzRect(fromCocoa: next.visibleFrame))
        default:
            preMaximizeFrames[key] = nil
            target = half(command, of: area)
        }
        AX.setFrame(target, of: window)
    }

    private static func half(_ command: Command, of area: CGRect) -> CGRect {
        let halfWidth = (area.width / 2).rounded()
        let halfHeight = (area.height / 2).rounded()
        switch command {
        case .leftHalf: return CGRect(x: area.minX, y: area.minY, width: halfWidth, height: area.height)
        case .rightHalf: return CGRect(x: area.maxX - halfWidth, y: area.minY, width: halfWidth, height: area.height)
        case .topHalf: return CGRect(x: area.minX, y: area.minY, width: area.width, height: halfHeight)
        case .bottomHalf: return CGRect(x: area.minX, y: area.maxY - halfHeight, width: area.width, height: halfHeight)
        default: return area
        }
    }

    /// 원래 모니터 안에서의 상대 위치와 크기 비율을 유지한 채 다른 모니터로 옮긴다.
    private static func relocate(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let scaleX = destination.width / source.width
        let scaleY = destination.height / source.height
        let width = min(frame.width * scaleX, destination.width)
        let height = min(frame.height * scaleY, destination.height)
        let x = destination.minX + (frame.minX - source.minX) * scaleX
        let y = destination.minY + (frame.minY - source.minY) * scaleY
        return CGRect(x: min(max(x, destination.minX), destination.maxX - width),
                      y: min(max(y, destination.minY), destination.maxY - height),
                      width: width, height: height).integral
    }
}
