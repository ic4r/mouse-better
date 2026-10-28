// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MouseBetter",
    platforms: [.macOS(.v14)],
    targets: [
        // 제스처 인식 로직 (AppKit 의존 없음, 단위 테스트 대상)
        .target(name: "GestureCore"),
        // 메뉴바 앱 본체
        .executableTarget(name: "MouseBetter", dependencies: ["GestureCore"]),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"]),
    ]
)
