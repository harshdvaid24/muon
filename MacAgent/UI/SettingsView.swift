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
    @AppStorage("hotkey") private var hotkey = HotKey.Preset.ctrlOptSpace.rawValue
    @AppStorage("sounds") private var sounds = true

    var body: some View {
        Form {
            Section("General") {
                Picker("Hotkey", selection: $hotkey) { ForEach(HotKey.Preset.allCases) { Text($0.rawValue).tag($0.rawValue) } }
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
