import Carbon.HIToolbox

/// Global hotkey via Carbon RegisterEventHotKey. No Accessibility permission required.
final class HotKey {
    enum Preset: String, CaseIterable, Identifiable {
        case shiftOptSpace = "⇧⌥Space", ctrlOptSpace = "⌃⌥Space", cmdOptSpace = "⌘⌥Space", cmdShiftSpace = "⌘⇧Space", ctrlShiftSpace = "⌃⇧Space", ctrlShiftA = "⌃⇧A"
        var id: String { rawValue }
        var keyCode: UInt32 { self == .ctrlShiftA ? 0 /* A */ : 49 /* space */ }
        var modifiers: UInt32 {
            switch self {
            case .shiftOptSpace: return UInt32(shiftKey | optionKey)
            case .ctrlOptSpace: return UInt32(controlKey | optionKey)
            case .cmdOptSpace: return UInt32(cmdKey | optionKey)
            case .cmdShiftSpace: return UInt32(cmdKey | shiftKey)
            case .ctrlShiftSpace: return UInt32(controlKey | shiftKey)
            case .ctrlShiftA: return UInt32(controlKey | shiftKey)
            }
        }
        // ⇧⌥Space by default; ⌘⇧Space is commonly taken (Gemini, input sources).
        static var current: Preset { Preset(rawValue: UserDefaults.standard.string(forKey: "hotkey") ?? "") ?? .shiftOptSpace }
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
        let installed = InstallEventHandler(GetEventDispatcherTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().handler()
            return noErr
        }, 1, &spec, userData, &handlerRef)
        guard installed == noErr else { HotKey.lastError = "event handler install failed (\(installed))"; return nil }
        let id = EventHotKeyID(signature: 0x4D41_4754, id: 1) // "MAGT"
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard status == noErr else { HotKey.lastError = "hotkey registration failed (\(status)); combination may be taken"; return nil }
        HotKey.lastError = nil
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

import AppKit

/// A recorded or preset shortcut.
struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon mask
    var label: String
}

extension HotKey {
    static let pauseNotification = Notification.Name("MuonHotKeyPause")
    static let resumeNotification = Notification.Name("MuonHotKeyResume")

    /// A recorded shortcut wins over the preset.
    static var currentCombo: HotKeyCombo {
        let d = UserDefaults.standard
        if let label = d.string(forKey: "hotkeyLabel"), d.object(forKey: "hotkeyCode") != nil {
            return HotKeyCombo(keyCode: UInt32(d.integer(forKey: "hotkeyCode")), modifiers: UInt32(d.integer(forKey: "hotkeyMods")), label: label)
        }
        let p = Preset.current
        return HotKeyCombo(keyCode: p.keyCode, modifiers: p.modifiers, label: p.rawValue)
    }

    static func save(_ c: HotKeyCombo?) {
        let d = UserDefaults.standard
        guard let c else { ["hotkeyCode", "hotkeyMods", "hotkeyLabel"].forEach(d.removeObject); return }
        d.set(Int(c.keyCode), forKey: "hotkeyCode")
        d.set(Int(c.modifiers), forKey: "hotkeyMods")
        d.set(c.label, forKey: "hotkeyLabel")
    }

    static func carbonModifiers(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    /// "⇧⌥Space", "⌃⌘K" …, in Apple's modifier order.
    static func label(for e: NSEvent) -> String {
        let f = e.modifierFlags
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        let named: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc", 122: "F1", 120: "F2", 99: "F3", 118: "F4",
                                       96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        return s + (named[e.keyCode] ?? (e.charactersIgnoringModifiers ?? "?").uppercased())
    }
}
