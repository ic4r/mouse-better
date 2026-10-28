import AppKit
import Carbon.HIToolbox

/// 맨 앞 앱의 포커스된 창을 AX 로 직접 옮기고 크기를 바꾼다.
@MainActor
enum WindowSnapper {
    enum Command {
        case leftHalf, rightHalf, topHalf, bottomHalf
        case nextScreen, toggleMaximize, toggleFullScreen, restoreOriginal
        case grow, shrink

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
            case .grow: return "크기 키우기 (가로 먼저, 다음 세로)"
            case .shrink: return "크기 줄이기 (가로·세로 함께)"
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
        (kVK_ANSI_Equal, "+", .grow),
        (kVK_ANSI_Minus, "-", .shrink),
    ]

    /// 크기를 한 번에 바꾸는 폭 (모니터 가용 영역 대비 비율)
    private static let resizeStep: CGFloat = 0.1
    private static let minimumSize = CGSize(width: 320, height: 240)

    /// AXUIElement 는 같은 창이면 CFEqual 이 참이므로 이를 딕셔너리 키로 쓴다.
    private struct WindowKey: Hashable {
        let element: AXUIElement
        static func == (lhs: WindowKey, rhs: WindowKey) -> Bool { CFEqual(lhs.element, rhs.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }

    private static var originalFrames: [WindowKey: CGRect] = [:]    // 처음 조작하기 전의 크기·위치
    private static var preMaximizeFrames: [WindowKey: CGRect] = [:] // 최대화 직전의 크기·위치
    /// visibleFrame 에 드러나지 않지만 시스템이 창을 들이지 않는 상단 영역 (모니터별로 실측해 기억)
    private static var topInsets: [CGDirectDisplayID: CGFloat] = [:]

    static func registerHotKeys(on center: HotKeyCenter) {
        let modifiers = controlKey | optionKey | cmdKey
        for binding in bindings {
            let command = binding.command
            center.register(keyCode: binding.keyCode, modifiers: modifiers) { perform(command) }
            // "+" 는 보통 Shift 와 함께 누르므로 Shift 조합도 같은 명령으로 받는다
            if command == .grow {
                center.register(keyCode: binding.keyCode, modifiers: modifiers | shiftKey) { perform(command) }
            }
        }
    }

    static func perform(_ command: Command) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = AX.element(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute)
        else { return }
        perform(command, on: window)
    }

    static func perform(_ command: Command, on window: AXUIElement) {
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

        switch command {
        case .toggleMaximize:
            if let previous = preMaximizeFrames.removeValue(forKey: key) {
                AX.setFrame(previous, of: window)
            } else {
                preMaximizeFrames[key] = current
                place(window, on: screen) { $0 }
            }
        case .nextScreen:
            guard let next = ScreenGeometry.screen(after: screen) else { return }
            let source = usableArea(of: screen)
            place(window, on: next) { relocate(current, from: source, to: $0) }
        case .grow, .shrink:
            preMaximizeFrames[key] = nil
            place(window, on: screen) { resize(current, grow: command == .grow, in: $0) }
        default:
            preMaximizeFrames[key] = nil
            place(window, on: screen) { half(command, of: $0) }
        }
    }

    // MARK: - 배치

    /// compute 로 계산한 위치에 창을 놓는다. 화면 위쪽 끝에 붙이려 했는데 시스템이 창을 아래로 밀어냈다면,
    /// 그 폭을 이 모니터의 상단 예약 영역으로 기억하고 다시 계산해 놓는다. 이후에는 처음부터 반영된다.
    private static func place(_ window: AXUIElement, on screen: NSScreen, _ compute: (CGRect) -> CGRect) {
        let area = usableArea(of: screen)
        let target = compute(area)
        AX.setFrame(target, of: window)

        guard abs(target.minY - area.minY) < 1, let actual = AX.frame(of: window) else { return }
        let pushedDown = actual.minY - target.minY
        guard pushedDown >= 1 else { return }
        topInsets[displayID(of: screen), default: 0] += pushedDown
        AX.setFrame(compute(usableArea(of: screen)), of: window)
    }

    /// 모니터에서 창을 놓을 수 있는 영역 (Quartz 좌표, 메뉴바·Dock·상단 예약 영역 제외)
    private static func usableArea(of screen: NSScreen) -> CGRect {
        var area = ScreenGeometry.quartzRect(fromCocoa: screen.visibleFrame)
        let inset = topInsets[displayID(of: screen)] ?? 0
        area.origin.y += inset
        area.size.height -= inset
        return area
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    // MARK: - 계산

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

    /// 크기는 유지하되(대상 모니터보다 크면 맞춰 줄임) 원래 모니터 안에서 중심이 있던 상대 위치로 옮긴다.
    /// 가로·세로 비율이 크게 다른 모니터(가로형 ↔ 세로형) 사이에서 창이 찌그러지지 않게 하기 위해서다.
    /// 원래 모니터를 가득 채운 창은 대상 모니터도 가득 채운다.
    private static func relocate(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        if frame.width >= source.width - 2, frame.height >= source.height - 2 {
            return destination
        }
        let size = CGSize(width: min(frame.width, destination.width), height: min(frame.height, destination.height))
        let center = CGPoint(
            x: destination.minX + (frame.midX - source.minX) / source.width * destination.width,
            y: destination.minY + (frame.midY - source.minY) / source.height * destination.height
        )
        return fit(size, centeredAt: center, in: destination)
    }

    /// 키우기: 가로를 먼저 모니터 폭까지 늘리고, 가로가 가득 차면 세로를 늘린다.
    /// 키우기·줄이기 모두 왼쪽 위 모서리를 고정한다. 키우다가 화면 오른쪽·아래 끝에 닿으면 그만큼만 안쪽으로 민다.
    private static func resize(_ frame: CGRect, grow: Bool, in area: CGRect) -> CGRect {
        let stepX = (area.width * resizeStep).rounded()
        let stepY = (area.height * resizeStep).rounded()
        var size = frame.size
        if grow {
            if size.width < area.width - 1 {
                size.width = min(size.width + stepX, area.width)
            } else {
                size.height = min(size.height + stepY, area.height)
            }
        } else {
            size.width = max(size.width - stepX, minimumSize.width)
            size.height = max(size.height - stepY, minimumSize.height)
        }
        let x = max(min(frame.minX, area.maxX - size.width), area.minX)
        let y = max(min(frame.minY, area.maxY - size.height), area.minY)
        return CGRect(x: x, y: y, width: size.width, height: size.height).integral
    }

    /// center 를 중심으로 size 크기의 사각형을 만들되, area 밖으로 나가면 안쪽으로 밀어 넣는다.
    private static func fit(_ size: CGSize, centeredAt center: CGPoint, in area: CGRect) -> CGRect {
        let width = min(size.width, area.width)
        let height = min(size.height, area.height)
        let x = min(max(center.x - width / 2, area.minX), area.maxX - width)
        let y = min(max(center.y - height / 2, area.minY), area.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height).integral
    }
}
