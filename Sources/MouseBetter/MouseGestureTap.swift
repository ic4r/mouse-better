import AppKit
import GestureCore

/// 우클릭 드래그를 전역으로 가로채 제스처로 처리한다.
///
/// - 우클릭 down 은 일단 삼킨다 (앱에 전달하면 컨텍스트 메뉴가 바로 떠 버린다).
/// - activationDistance 이상 움직이면 제스처로 보고 궤적을 그린다.
/// - 거의 움직이지 않고 놓았으면 삼켰던 down/up 을 다시 보내 원래 우클릭으로 동작시킨다.
@MainActor
final class MouseGestureTap {
    /// 우리가 다시 보낸 이벤트를 식별하는 표식 (eventSourceUserData 필드)
    private static let replayMarker: Int64 = 0x4D42_4554  // "MBET"
    private let activationDistance: CGFloat = 12

    private let overlay: TrailOverlay
    private let recognizer = GestureRecognizer()
    private var tap: CFMachPort?

    private var tracking = false   // 우클릭 down 을 삼킨 상태
    private var drawing = false    // 제스처로 판정되어 궤적을 그리는 상태
    private var points: [CGPoint] = []
    private var swallowedDown: CGEvent?

    var isEnabled = true

    init(overlay: TrailOverlay) {
        self.overlay = overlay
    }

    func start() {
        guard tap == nil else { return }
        let types: [CGEventType] = [.rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                // 탭은 메인 런루프에 붙어 있으므로 메인 스레드에서 호출된다
                MainActor.assumeIsolated {
                    let me = Unmanaged<MouseGestureTap>.fromOpaque(refcon!).takeUnretainedValue()
                    return me.handle(type: type, event: event)
                }
            },
            userInfo: refcon
        ) else {
            NSLog("MouseBetter: 이벤트 탭 생성 실패 (손쉬운 사용 권한 확인 필요)")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // 콜백이 늦으면 시스템이 탭을 꺼 버리므로 다시 켠다
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker {
            return pass
        }

        let location = event.location
        switch type {
        case .rightMouseDown:
            guard isEnabled else { return pass }
            tracking = true
            drawing = false
            points = [location]
            swallowedDown = event.copy()
            return nil

        case .rightMouseDragged:
            guard tracking else { return pass }
            points.append(location)
            if !drawing, distance(points[0], location) >= activationDistance {
                drawing = true
                overlay.begin(with: points)
            } else if drawing {
                overlay.extend(to: location)
            }
            return nil

        case .rightMouseUp:
            guard tracking else { return pass }
            tracking = false
            if drawing {
                drawing = false
                let gesture = Gesture(directions: recognizer.directions(of: points))
                overlay.finish(recognized: gesture != nil)
                if let gesture {
                    let origin = points[0]
                    DispatchQueue.main.async { Actions.perform(gesture, startedAt: origin) }
                }
            } else {
                replayClick(up: event)
            }
            return nil

        default:
            return pass
        }
    }

    private func replayClick(up: CGEvent) {
        guard let down = swallowedDown, let up = up.copy() else { return }
        swallowedDown = nil
        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }
}
