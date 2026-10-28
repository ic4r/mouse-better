import CoreGraphics

/// 화면 좌표계는 Quartz 기준이다 (원점 좌상단, y 가 아래로 증가).
public enum Direction: Equatable {
    case up, down, left, right
}

/// 궤적을 상하좌우 방향열로 바꾼다.
///
/// 1. 일정 거리(sampleStep)마다 직전 지점 대비 우세한 축으로 방향을 정한다.
/// 2. 같은 방향이 이어지면 하나의 구간으로 합치고 길이를 누적한다.
/// 3. minSegmentLength 보다 짧은 구간(손떨림)은 버리고, 버린 뒤 이웃한 같은 방향을 다시 합친다.
public struct GestureRecognizer {
    public var sampleStep: CGFloat
    public var minSegmentLength: CGFloat

    public init(sampleStep: CGFloat = 8, minSegmentLength: CGFloat = 40) {
        self.sampleStep = sampleStep
        self.minSegmentLength = minSegmentLength
    }

    public func directions(of points: [CGPoint]) -> [Direction] {
        guard var anchor = points.first else { return [] }

        var segments: [(direction: Direction, length: CGFloat)] = []
        for point in points.dropFirst() {
            let dx = point.x - anchor.x
            let dy = point.y - anchor.y
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance >= sampleStep else { continue }

            let direction: Direction = abs(dx) > abs(dy)
                ? (dx > 0 ? .right : .left)
                : (dy > 0 ? .down : .up)
            if let last = segments.last, last.direction == direction {
                segments[segments.count - 1].length += distance
            } else {
                segments.append((direction, distance))
            }
            anchor = point
        }

        var result: [Direction] = []
        for segment in segments where segment.length >= minSegmentLength {
            if result.last != segment.direction {
                result.append(segment.direction)
            }
        }
        return result
    }
}

extension Direction {
    public var arrow: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        }
    }
}

public enum Gesture: CaseIterable {
    case closeTab
    case reload
    case previousApp
    case scrollToBottom
    case scrollToTop

    /// 방향열 → 제스처 매핑. 메뉴바의 기능 목록도 이 표로 만든다.
    /// 제스처를 추가할 때는 여기에 한 줄, Actions.perform 에 동작 한 줄을 추가한다.
    public static let bindings: [(directions: [Direction], gesture: Gesture)] = [
        ([.down, .right], .closeTab),     // ㄴ
        ([.down, .left], .reload),
        ([.right, .down], .previousApp),  // ㄱ
        ([.down], .scrollToBottom),
        ([.up], .scrollToTop),
    ]

    public init?(directions: [Direction]) {
        guard let binding = Self.bindings.first(where: { $0.directions == directions }) else { return nil }
        self = binding.gesture
    }

    public var title: String {
        switch self {
        case .closeTab: return "탭 닫기"
        case .reload: return "새로고침"
        case .previousApp: return "이전 앱으로 전환"
        case .scrollToBottom: return "맨 아래로 스크롤"
        case .scrollToTop: return "맨 위로 스크롤"
        }
    }
}
