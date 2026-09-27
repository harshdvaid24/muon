import ApplicationServices
import Carbon
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Settings.Key.model) private var model = "qwen/qwen3.5-9b"
    @AppStorage(Settings.Key.fallbackModel) private var fallbackModel = "qwen/qwen3.5-4b"
    @AppStorage(Settings.Key.modelTTL) private var ttl = 300
    @AppStorage(Settings.Key.lmBaseURL) private var lmBaseURL = "http://127.0.0.1:1234"
    @AppStorage(Settings.Key.confidence) private var confidence = 0.6
    @AppStorage(Settings.Key.nodePath) private var nodePath = ""
    @AppStorage(Settings.Key.mcpServerPath) private var mcpServerPath = ""
    @State private var roots = Settings.allowedRoots.joined(separator: "\n")
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var macros = Agent.shared.memory?.macros() ?? []
    @State private var rules = Rules.all
    @AppStorage(ScreenshotWatcher.settingKey) private var autoName = false
    @AppStorage("layaEnabled") private var layaEnabled = true
    @AppStorage("needleEnabled") private var needleEnabled = false
    @AppStorage("needleURL") private var needleURL = "http://127.0.0.1:8766"
    @AppStorage("layaURL") private var layaURL = "http://127.0.0.1:8765"
    @AppStorage("hotkey") private var hotkey = HotKey.Preset.shiftOptSpace.rawValue
    @AppStorage("sounds") private var sounds = true
    @AppStorage(Settings.Key.voiceAutoListen) private var voiceAutoListen = false
    @AppStorage(Settings.Key.speakReplies) private var speakReplies = true
    @State private var axTrusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section("General") {
                ShortcutRecorder()
                Picker("Preset", selection: $hotkey) { ForEach(HotKey.Preset.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                    .onChange(of: hotkey) { HotKey.save(nil) }   // choosing a preset clears a recorded shortcut
                if let err = HotKey.lastError {
                    Text("\(err). Another app (e.g. Gemini owns ⌘⇧Space) may have this combination; pick another.").font(.caption).foregroundStyle(.red)
                } else {
                    Text("If the hotkey does nothing, another app already owns it — pick a different combination.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Sound effects", isOn: $sounds)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil }
                        catch { loginError = error.localizedDescription; launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.secondary) }
                LabeledContent("On-device model") { Text(FoundationTier.isAvailable ? "Available" : (FoundationTier.unavailableReason ?? "Unavailable")).foregroundStyle(.secondary) }
            }
            Section("App control") {
                LabeledContent("Accessibility") {
                    HStack(spacing: 8) {
                        Image(systemName: axTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(axTrusted ? .green : .orange)
                        Text(axTrusted ? "Granted" : "Not granted")
                        if !axTrusted {
                            Button("Grant…") {
                                AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                            }
                        }
                    }
                }
                Text("Needed to run menu commands in other apps (runMenuCommand). Read-only tools don't need it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local model (LM Studio)") {
                TextField("Model", text: $model)
                TextField("Low-memory fallback", text: $fallbackModel)
                TextField("Server URL", text: $lmBaseURL)
                Stepper("Unload after \(ttl) s idle", value: $ttl, in: 60...3600, step: 60)
                Slider(value: $confidence, in: 0.3...0.95, step: 0.05) { Text("Escalate below confidence \(confidence, format: .number.precision(.fractionLength(2)))") }
            }
            Section("Allowed folders (one per line)") {
                TextEditor(text: $roots)
                    .font(.body.monospaced())
                    .frame(minHeight: 96)
                    .onChange(of: roots) { _, v in
                        Settings.d.set(v.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, forKey: Settings.Key.allowedRoots)
                        MCPClient.shared.stop()
                        Agent.shared.refreshProjects()
                    }
                Text("Protected locations (~/Library, ~/.ssh, /System, …) are always refused, even inside these folders.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Tool server") {
                TextField("Node binary", text: $nodePath, prompt: Text(Settings.probeNode() ?? "/usr/local/bin/node"))
                TextField("mac-tools index.js", text: $mcpServerPath, prompt: Text(Settings.mcpServerPath))
                Button("Forget “always allow” choices") { Settings.d.removeObject(forKey: Settings.Key.alwaysAllow) }
            }
            Section("Voice") {
                Toggle("Start listening when the palette opens", isOn: $voiceAutoListen)
                Toggle("Speak replies to spoken requests", isOn: $speakReplies)
                Text("Press ⌘⇧M or click the mic, say what you need and pause; it runs. Speech is recognized on-device and nothing is recorded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Automation") {
                Toggle("Name new screenshots by their content", isOn: $autoName)
                    .onChange(of: autoName) { ScreenshotWatcher.shared.apply() }
                Text("Watches your screenshots folder; each new screenshot is renamed like 2026-08-01-invoice-acme.png. Type “undo” to revert the last one.")
                    .font(.caption).foregroundStyle(.secondary)
                if rules.isEmpty {
                    Text("No rules yet. Ask “every monday move the screenshots in ~/Downloads older than 30 days into ~/Downloads/Archive”, or accept a suggestion in the palette.").foregroundStyle(.secondary)
                }
                ForEach(rules) { r in
                    HStack {
                        VStack(alignment: .leading) { Text(r.query).lineLimit(1); Text(r.schedule.label).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Delete", role: .destructive) { Rules.remove(id: r.id); rules = Rules.all }
                    }
                }
            }
            Section("Laya (optional fast decisions)") {
                Toggle("Use Laya when running", isOn: $layaEnabled)
                TextField("Server URL", text: $layaURL)
                Text("pip install \"laya[serve]\" then LAYA_PORT=8765 laya-serve. Adds ~150 ms routing hints and lets you type requests in 100+ languages (translated via LM Studio).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Needle (experimental fast tool calls)") {
                Toggle("Use Needle when running", isOn: $needleEnabled)
                TextField("Server URL", text: $needleURL)
                Text("Needle 3 (cactus-needle) is a 29 MB tool-calling model: ~50 ms per decision. It acts only when at least 90% sure and only on tools that cannot change anything without a card; otherwise the on-device model answers as usual. The palette footer shows which one answered. Start it with: python3 -m venv ~/.muon/needle && ~/.muon/needle/bin/pip install cactus-needle && ~/.muon/needle/bin/python scripts/needle-serve.py")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Macros") {
                if macros.isEmpty {
                    Text("None yet. After a multi-step request, type “save macro <name>”.").foregroundStyle(.secondary)
                }
                ForEach(macros, id: \.name) { m in
                    HStack {
                        Text(m.name)
                        Spacer()
                        Button("Delete", role: .destructive) { Agent.shared.memory?.deleteMacro(m.name); macros = Agent.shared.memory?.macros() ?? [] }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
    }
}


/// Click "Record", press the keys you want; Muon registers exactly what the keyboard sends.
struct ShortcutRecorder: View {
    @State private var label = HotKey.currentCombo.label
    @State private var recording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        LabeledContent("Shortcut") {
            HStack(spacing: 8) {
                Text(recording ? "Press keys…" : label)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.quaternary, in: .rect(cornerRadius: 6))
                Button(recording ? "Cancel" : "Record") { recording ? stop() : start() }
            }
        }
        if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
    }

    private func start() {
        hint = "Press the shortcut you want, including ⌘, ⌥, ⌃ or ⇧."
        recording = true
        NotificationCenter.default.post(name: HotKey.pauseNotification, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = HotKey.carbonModifiers(e.modifierFlags)
            if e.keyCode == 53, mods == 0 { stop(); return nil }                        // Esc cancels
            guard mods & UInt32(cmdKey | optionKey | controlKey) != 0 else {
                hint = "Add ⌘, ⌥ or ⌃ so normal typing is not captured."; return nil
            }
            let combo = HotKeyCombo(keyCode: UInt32(e.keyCode), modifiers: mods, label: HotKey.label(for: e))
            HotKey.save(combo)
            label = combo.label
            hint = "Shortcut set to \(combo.label)."
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        NotificationCenter.default.post(name: HotKey.resumeNotification, object: nil)
    }
}
