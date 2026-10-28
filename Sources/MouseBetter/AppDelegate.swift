import AppKit
import GestureCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = TrailOverlay()
    private lazy var gestureTap = MouseGestureTap(overlay: overlay)
    private let hotKeys = HotKeyCenter()
    private var permissionTimer: Timer?

    private let enabledItem = NSMenuItem(title: "마우스 제스처 사용", action: #selector(toggleEnabled), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "로그인 시 실행", action: #selector(toggleLoginItem), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        AppHistory.shared.start()
        WindowSnapper.registerHotKeys(on: hotKeys)
        startWhenTrusted()
    }

    // MARK: - 권한

    /// 손쉬운 사용 권한이 있어야 이벤트 탭을 만들 수 있다. 권한이 생길 때까지 2초마다 확인한다.
    private func startWhenTrusted() {
        if Permissions.isTrusted(prompt: true) {
            gestureTap.start()
        } else {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self, Permissions.isTrusted(prompt: false) else { return }
                    timer.invalidate()
                    self.gestureTap.start()
                    self.refreshMenu()
                }
            }
        }
        refreshMenu()
    }

    // MARK: - 메뉴

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "scribble.variable", accessibilityDescription: "MouseBetter")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.addItem(withTitle: "MouseBetter", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        for item in [enabledItem, permissionItem, loginItem] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        addFeatureList(to: menu)
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    /// 제스처·단축키 매핑 표를 그대로 읽어 기능 목록을 보여 준다. 매핑을 바꾸면 메뉴도 따라 바뀐다.
    private func addFeatureList(to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: "마우스 제스처 (우클릭 드래그)"))
        for binding in Gesture.bindings {
            let shape = binding.directions.map(\.arrow).joined(separator: " ")
            menu.addItem(featureItem(key: shape, title: binding.gesture.title))
        }
        menu.addItem(.sectionHeader(title: "창 단축키 (\(WindowSnapper.modifierLabel) + 키)"))
        for binding in WindowSnapper.bindings {
            menu.addItem(featureItem(key: binding.keyLabel, title: binding.command.title))
        }
    }

    /// 왼쪽에 입력, 탭 정렬 후 오른쪽에 기능 이름을 표시하는 안내용 항목
    private func featureItem(key: String, title: String) -> NSMenuItem {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .left, location: 64)]
        let font = NSFont.menuFont(ofSize: 0)
        let text = NSMutableAttributedString(string: "\(key)\t\(title)",
                                             attributes: [.font: font, .paragraphStyle: style])
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = text
        item.isEnabled = false
        return item
    }

    private func refreshMenu() {
        enabledItem.state = gestureTap.isEnabled ? .on : .off
        permissionItem.title = Permissions.isTrusted(prompt: false)
            ? "손쉬운 사용 권한: 허용됨"
            : "손쉬운 사용 권한 필요 (클릭하여 설정 열기)"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleEnabled() {
        gestureTap.isEnabled.toggle()
        refreshMenu()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("MouseBetter: 로그인 항목 변경 실패: \(error)")
        }
        refreshMenu()
    }
}

enum Permissions {
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }
}
