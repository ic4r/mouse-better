import AppKit

/// 모니터마다 투명하고 클릭이 통과하는 창을 하나씩 띄워 궤적을 그린다.
/// 궤적은 Quartz 전역 좌표(원점 좌상단)로 보관하고, 창마다 자기 좌표계로 변환해 그린다.
@MainActor
final class TrailOverlay {
    private struct Canvas {
        let window: NSWindow
        let layer: CAShapeLayer
    }

    private var canvases: [Canvas] = []
    private var screenFrames: [CGRect] = []
    private var path = CGMutablePath()
    private var generation = 0  // 사라지는 애니메이션 도중 새 제스처가 시작된 경우를 구분한다

    private let drawingColor = NSColor.systemBlue.withAlphaComponent(0.85).cgColor
    private let recognizedColor = NSColor.systemGreen.withAlphaComponent(0.85).cgColor
    private let rejectedColor = NSColor.systemGray.withAlphaComponent(0.6).cgColor

    func begin(with points: [CGPoint]) {
        rebuildCanvasesIfNeeded()
        generation += 1
        path = CGMutablePath()
        path.move(to: points[0])
        path.addLines(between: points)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for canvas in canvases {
            canvas.layer.strokeColor = drawingColor
            canvas.layer.opacity = 1
            canvas.window.orderFrontRegardless()
        }
        CATransaction.commit()
        redraw()
    }

    func extend(to point: CGPoint) {
        path.addLine(to: point)
        redraw()
    }

    func finish(recognized: Bool) {
        let current = generation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvases.forEach { $0.layer.strokeColor = recognized ? recognizedColor : rejectedColor }
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.canvases.forEach { $0.window.orderOut(nil) }
            }
        }
        canvases.forEach { $0.layer.opacity = 0 }
        CATransaction.commit()
    }

    private func redraw() {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for canvas in canvases {
            // Quartz 전역 (x, y) → 창 로컬 (x - minX, primaryHeight - minY - y)
            let frame = canvas.window.frame
            var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                              tx: -frame.minX, ty: primaryHeight - frame.minY)
            canvas.layer.path = path.copy(using: &transform)
        }
        CATransaction.commit()
    }

    private func rebuildCanvasesIfNeeded() {
        let frames = NSScreen.screens.map(\.frame)
        guard frames != screenFrames else { return }
        canvases.forEach { $0.window.close() }
        screenFrames = frames
        canvases = frames.map(makeCanvas)
    }

    private func makeCanvas(frame: CGRect) -> Canvas {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.setFrame(frame, display: false)

        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        let layer = CAShapeLayer()
        layer.frame = view.bounds
        layer.fillColor = nil
        layer.lineWidth = 5
        layer.lineCap = .round
        layer.lineJoin = .round
        view.layer?.addSublayer(layer)
        window.contentView = view
        return Canvas(window: window, layer: layer)
    }
}
