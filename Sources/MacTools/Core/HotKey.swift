import Carbon.HIToolbox

/// A registered global hotkey via Carbon's RegisterEventHotKey.
/// Supports multiple concurrent hotkeys, dispatched by id through a shared handler table.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    private static var handlers: [UInt32: () -> Void] = [:]
    private static var eventHandlerInstalled = false

    init?(shortcut: Shortcut, id: UInt32, handler: @escaping () -> Void) {
        guard let keyCode = shortcut.keyCode else { return nil }
        self.id = id
        HotKey.installDispatcherIfNeeded()
        HotKey.handlers[id] = handler
        guard register(keyCode: keyCode, modifiers: shortcut.carbonModifiers) else { return nil }
    }

    private static func installDispatcherIfNeeded() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hkID
                )
                HotKey.handlers[hkID.id]?()
                return noErr
            },
            1, &eventType, nil, nil
        )
    }

    private func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D544C53 /* "MTLS" */), id: id)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        return status == noErr
    }

    deinit {
        if let hotKeyRef = hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        HotKey.handlers[id] = nil
    }
}
