import Carbon.HIToolbox

/// Carbon RegisterEventHotKey 로 전역 단축키를 등록한다.
/// 이벤트 탭과 달리 손쉬운 사용 권한 없이 동작하고, 등록한 조합만 가로채므로 다른 키 입력에 영향이 없다.
@MainActor
final class HotKeyCenter {
    private static let signature: OSType = 0x4D42_4554  // "MBET"

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, refcon in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            MainActor.assumeIsolated {
                let center = Unmanaged<HotKeyCenter>.fromOpaque(refcon!).takeUnretainedValue()
                center.handlers[hotKeyID.id]?()
            }
            return noErr
        }, 1, &spec, refcon, &eventHandler)
    }

    /// keyCode 는 kVK_* , modifiers 는 Carbon 수식키 마스크(cmdKey, optionKey, controlKey, shiftKey)의 조합이다.
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("MouseBetter: 단축키 등록 실패 keyCode=\(keyCode) status=\(status)")
            return
        }
        refs.append(ref)
        handlers[id] = handler
    }
}
