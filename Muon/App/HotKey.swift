import Carbon.HIToolbox

/// Global hotkey via Carbon RegisterEventHotKey. No Accessibility permission required.
final class HotKey {
    enum Preset: String, CaseIterable, Identifiable {
        case ctrlOptSpace = "⌃⌥Space", cmdOptSpace = "⌘⌥Space", cmdShiftSpace = "⌘⇧Space", ctrlShiftSpace = "⌃⇧Space", ctrlShiftA = "⌃⇧A"
        var id: String { rawValue }
        var keyCode: UInt32 { self == .ctrlShiftA ? 0 /* A */ : 49 /* space */ }
        var modifiers: UInt32 {
            switch self {
            case .ctrlOptSpace: return UInt32(controlKey | optionKey)
            case .cmdOptSpace: return UInt32(cmdKey | optionKey)
            case .cmdShiftSpace: return UInt32(cmdKey | shiftKey)
            case .ctrlShiftSpace: return UInt32(controlKey | shiftKey)
            case .ctrlShiftA: return UInt32(controlKey | shiftKey)
            }
        }
        // ⌃⌥Space is free by default; ⌘⇧Space is commonly taken (Gemini, input sources).
        static var current: Preset { Preset(rawValue: UserDefaults.standard.string(forKey: "hotkey") ?? "") ?? .ctrlOptSpace }
    }

    /// Set when registration fails (e.g. combination already taken by another app).
    static var lastError: String?
    /// ⌃⌥ modifier mask for RegisterEventHotKey.
    static let controlOption = UInt32(controlKey | optionKey)
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().handler()
            return noErr
        }, 1, &spec, userData, &handlerRef)
        guard installed == noErr else { HotKey.lastError = "event handler install failed (\(installed))"; return nil }
        let id = EventHotKeyID(signature: 0x4D41_4754, id: 1) // "MAGT"
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else { HotKey.lastError = "hotkey registration failed (\(status)); combination may be taken"; return nil }
        HotKey.lastError = nil
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
