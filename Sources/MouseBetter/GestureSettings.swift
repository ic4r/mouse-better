import AppKit

/// 마우스 제스처 사용 여부와 예외 앱 목록. UserDefaults 에 저장해 앱을 다시 실행해도 유지한다.
@MainActor
final class GestureSettings {
    static let shared = GestureSettings()

    private static let enabledKey = "gesturesEnabled"
    private static let excludedKey = "excludedBundleIDs"
    /// 처음 실행할 때 기본으로 제외하는 앱: 우클릭 드래그를 직접 쓰는 게임(Roblox)과 터미널(iTerm)
    private static let defaultExcluded = ["com.roblox.RobloxPlayer", "com.googlecode.iterm2"]

    private let defaults = UserDefaults.standard
    private(set) var excluded: Set<String>

    /// 설정이 바뀌면 호출된다 (메뉴바 아이콘·메뉴 갱신용)
    var onChange: (() -> Void)?

    private init() {
        excluded = Set(defaults.stringArray(forKey: Self.excludedKey) ?? Self.defaultExcluded)
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            onChange?()
        }
    }

    func isExcluded(_ bundleID: String) -> Bool {
        excluded.contains(bundleID)
    }

    func setExcluded(_ bundleID: String, _ exclude: Bool) {
        if exclude {
            excluded.insert(bundleID)
        } else {
            excluded.remove(bundleID)
        }
        defaults.set(excluded.sorted(), forKey: Self.excludedKey)
        onChange?()
    }

    /// 제스처는 커서 아래 창에 동작하므로, 맨 앞 앱이 아니라 우클릭한 위치의 창을 가진 앱으로 판단한다.
    /// 창을 찾지 못하면(전체 화면 게임 등) 맨 앞 앱으로 판단한다.
    func shouldHandleGesture(at point: CGPoint) -> Bool {
        guard isEnabled else { return false }
        let pid = Actions.topWindow(at: point)?.pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let pid, let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return true }
        return !excluded.contains(bundleID)
    }

    /// 예외 목록에 표시할 앱 이름. 설치 위치를 찾지 못하면 번들 ID 를 그대로 쓴다.
    static func displayName(of bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
