// 메뉴바 아이콘과 같은 SF Symbol(scribble.variable)로 앱 아이콘(Resources/AppIcon.icns)을 만든다.
// 사용법: swift scripts/make-icon.swift  (저장소 루트에서 실행)
import AppKit

let symbolName = "scribble.variable"
let fileManager = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS 아이콘 그리드: 1024 캔버스에 824 크기의 둥근 사각형, 모서리 반경 약 185
    let unit = CGFloat(pixels) / 1024
    let plate = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let path = NSBezierPath(roundedRect: plate, xRadius: 185 * unit, yRadius: 185 * unit)
    NSGradient(starting: NSColor(srgbRed: 0.27, green: 0.55, blue: 1.0, alpha: 1),
               ending: NSColor(srgbRed: 0.36, green: 0.26, blue: 0.86, alpha: 1))!
        .draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: 480 * unit, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let symbolSize = symbol.size
    symbol.draw(in: NSRect(x: plate.midX - symbolSize.width / 2, y: plate.midY - symbolSize.height / 2,
                           width: symbolSize.width, height: symbolSize.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).write(to: iconset.appendingPathComponent(name))
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try process.run()
process.waitUntilExit()
print(process.terminationStatus == 0 ? "created: Resources/AppIcon.icns" : "iconutil failed")
