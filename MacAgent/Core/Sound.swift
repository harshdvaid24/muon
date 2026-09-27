import AppKit

/// Subtle audio feedback using built-in macOS system sounds. Off via Settings.
enum Sound {
    enum Cue { case appear, success, prompt, error, cancel }

    static var enabled: Bool { Settings.d.object(forKey: "sounds") as? Bool ?? true }

    static func play(_ cue: Cue) {
        guard enabled else { return }
        let name: String
        switch cue {
        case .appear:  name = "Pop"      // opening the palette
        case .success: name = "Tink"     // an action completed
        case .prompt:  name = "Purr"     // a confirmation is being asked
        case .error:   name = "Basso"    // something failed
        case .cancel:  name = "Bottle"   // user cancelled
        }
        NSSound(named: name)?.play()
    }
}
