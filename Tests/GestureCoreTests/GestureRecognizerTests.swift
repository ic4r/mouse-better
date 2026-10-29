import CoreGraphics
import Testing
@testable import GestureCore

/// 시작점에서 (dx, dy) 만큼씩 이동하는 궤적을 step 간격으로 만든다.
private func stroke(from start: CGPoint = .init(x: 500, y: 500), _ moves: (CGFloat, CGFloat)..., step: CGFloat = 4) -> [CGPoint] {
    var points = [start]
    var current = start
    for (dx, dy) in moves {
        let count = Int(max(abs(dx), abs(dy)) / step)
        for i in 1...max(count, 1) {
            let t = CGFloat(i) / CGFloat(max(count, 1))
            points.append(CGPoint(x: current.x + dx * t, y: current.y + dy * t))
        }
        current = CGPoint(x: current.x + dx, y: current.y + dy)
    }
    return points
}

private let recognizer = GestureRecognizer()

@Test func lShapeClosesTab() {
    let dirs = recognizer.directions(of: stroke((0, 200), (150, 0)))
    #expect(dirs == [.down, .right])
    #expect(Gesture(directions: dirs) == .closeTab)
}

@Test func giyeokShapeSwitchesToPreviousApp() {
    let dirs = recognizer.directions(of: stroke((150, 0), (0, 200)))
    #expect(Gesture(directions: dirs) == .previousApp)
}

@Test func downThenLeftReloads() {
    let dirs = recognizer.directions(of: stroke((0, 200), (-150, 0)))
    #expect(Gesture(directions: dirs) == .reload)
}

@Test func horizontalStrokesNavigate() {
    #expect(Gesture(directions: recognizer.directions(of: stroke((-250, 0)))) == .back)
    #expect(Gesture(directions: recognizer.directions(of: stroke((250, 0)))) == .forward)
}

@Test func everyGestureHasExactlyOneBinding() {
    for gesture in Gesture.allCases {
        #expect(Gesture.bindings.filter { $0.gesture == gesture }.count == 1)
    }
    let keys = Gesture.bindings.map { $0.directions.map(\.arrow).joined() }
    #expect(Set(keys).count == keys.count)
}

@Test func verticalStrokesScroll() {
    #expect(Gesture(directions: recognizer.directions(of: stroke((0, 250)))) == .scrollToBottom)
    #expect(Gesture(directions: recognizer.directions(of: stroke((0, -250)))) == .scrollToTop)
}

@Test func jitterIsIgnored() {
    // 아래로 긋는 도중 옆으로 살짝 흔들려도 한 방향으로 본다
    let dirs = recognizer.directions(of: stroke((0, 120), (10, 2), (0, 120), (-12, 0), (0, 80)))
    #expect(dirs == [.down])
}

@Test func slightlyTiltedStrokeStillCounts() {
    let dirs = recognizer.directions(of: stroke((30, 220), (180, 25)))
    #expect(dirs == [.down, .right])
}

@Test func tinyMovementIsNotAGesture() {
    #expect(recognizer.directions(of: stroke((10, 15))).isEmpty)
}

@Test func unknownShapeIsNil() {
    #expect(Gesture(directions: [.left, .up, .right]) == nil)
}
