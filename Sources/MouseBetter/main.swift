import AppKit

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)  // Dock 아이콘 없이 메뉴바에만 상주
app.run()
