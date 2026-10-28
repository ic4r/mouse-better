import AppKit

/// 앱 활성화 순서를 기록해 ⌘Tab 처럼 직전 앱으로 돌아간다.
/// 키 합성 대신 직접 활성화하므로 앱 전환기 UI 가 뜨지 않고, 키 입력 타이밍에 영향을 받지 않는다.
@MainActor
final class AppHistory {
    static let shared = AppHistory()

    private var recent: [pid_t] = []  // 최근에 활성화된 순서 (0번이 가장 최근)
    private var observer: NSObjectProtocol?

    func start() {
        if let front = NSWorkspace.shared.frontmostApplication {
            record(front.processIdentifier)
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.record(pid) }
        }
    }

    func activatePrevious() {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for pid in recent where pid != front {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { continue }
            AX.activate(pid: pid)
            return
        }
    }

    private func record(_ pid: pid_t) {
        guard pid != getpid() else { return }
        recent.removeAll { $0 == pid }
        recent.insert(pid, at: 0)
        if recent.count > 20 { recent.removeLast() }
    }
}
