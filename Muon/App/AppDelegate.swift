import AppKit
import ApplicationServices
import Carbon
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Explicit entry point: without a MainMenu nib, NSApplicationMain would never instantiate the delegate.
    static func main() {
        signal(SIGPIPE, SIG_IGN) // a dead tool-server pipe must never kill the app
        Self.migrateSupportDir()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.mainMenu = Self.makeMainMenu()
        _ = CLI.runIfRequested()
        app.run()
    }

    /// AppKit routes ⌘Z/⌘X/⌘C/⌘A through the Edit menu; a menu bar app has none unless it builds one.
    /// ⌘V is left out on purpose: the palette handles it (attach a copied file or image, else paste text).
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Muon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return main
    }

    /// One-time move of the pre-rename support folder (learned memory, audit log) to the new name.
    private static func migrateSupportDir() {
        let base = NSHomeDirectory() + "/Library/Application Support/"
        let new = base + "Muon"
        let fm = FileManager.default
        guard !fm.fileExists(atPath: new) else { return }
        for old in ["Wisp", "MacAgent"] where fm.fileExists(atPath: base + old) {
            try? fm.moveItem(atPath: base + old, toPath: new); return
        }
    }

    private var statusItem: NSStatusItem!
    let palette = PanelController()
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:with:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    /// Finder › Open With › Muon (or `open -a Muon file`): attach the file and wait for the request.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: \.isFileURL) else { return }
        palette.show(anchor: nil)
        let m = palette.model
        m.attachment = url.path
        m.query = ""
        m.rows = []; m.answer = nil; m.result = nil; m.footer = nil
        m.note = "Attached \(url.lastPathComponent). Ask anything: give me a brief · analyse it · what is the total · fix grammar"
        m.focusRequest += 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || CLI.active { return }
        wireAgent()
        setupStatusItem()
        registerHotKey()
        observeHotKeyPause()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.registerHotKey() }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private var registeredCombo: HotKeyCombo?
    private var hotKeyPaused = false
    private func registerHotKey() {
        guard !hotKeyPaused else { return }
        let combo = HotKey.currentCombo
        guard combo != registeredCombo || hotKey == nil else { return }
        hotKey = nil
        hotKey = HotKey(keyCode: combo.keyCode, modifiers: combo.modifiers) { [weak self] in self?.palette.toggle(anchor: nil) }
        registeredCombo = hotKey == nil ? nil : combo
        if let err = HotKey.lastError { NSLog("Muon: %@ for %@", err, combo.label) }
    }

    /// The Settings recorder pauses the global shortcut so the keys reach it instead of opening the palette.
    private func observeHotKeyPause() {
        NotificationCenter.default.addObserver(forName: HotKey.pauseNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hotKeyPaused = true; self?.hotKey = nil; self?.registeredCombo = nil }
        }
        NotificationCenter.default.addObserver(forName: HotKey.resumeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hotKeyPaused = false; self?.registerHotKey() }
        }
    }

    // MARK: Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        let image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Muon")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        button.image = image
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            palette.toggle(anchor: sender.window?.frame)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let ask = NSMenuItem(title: "Ask Muon…   \(HotKey.currentCombo.label)", action: #selector(openPalette), keyEquivalent: "")
        ask.target = self
        menu.addItem(ask)
        let talk = NSMenuItem(title: "Talk to Muon…   ⌘⇧M", action: #selector(talk), keyEquivalent: "")
        talk.target = self
        menu.addItem(talk)
        menu.addItem(.separator())
        let modelItem = NSMenuItem(title: "Model: checking…", action: nil, keyEquivalent: "")
        menu.addItem(modelItem)
        Task { @MainActor in
            let loaded = await LMStudioTier.loadedModels()
            modelItem.title = loaded.isEmpty ? "Model: not loaded (0 GB)" : "Model loaded: \(loaded.joined(separator: ", "))"
        }
        let unload = NSMenuItem(title: "Unload Model Now", action: #selector(unloadModel), keyEquivalent: "")
        unload.target = self
        menu.addItem(unload)
        let stopTools = NSMenuItem(title: MCPClient.shared.isRunning ? "Stop Tool Server (running)" : "Tool Server: idle", action: #selector(stopToolServer), keyEquivalent: "")
        stopTools.target = self
        stopTools.isEnabled = MCPClient.shared.isRunning
        menu.addItem(stopTools)
        menu.addItem(.separator())
        let macros = Agent.shared.memory?.macros() ?? []
        if !macros.isEmpty {
            let sub = NSMenu()
            for m in macros {
                let item = NSMenuItem(title: m.name, action: #selector(runMacro(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = m.name
                sub.addItem(item)
            }
            let macrosItem = NSMenuItem(title: "Macros", action: nil, keyEquivalent: "")
            macrosItem.submenu = sub
            menu.addItem(macrosItem)
        }
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Muon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPalette() { palette.show(anchor: nil) }

    @objc private func talk() {
        palette.show(anchor: nil)
        Task { await Voice.shared.start() }
    }

    /// ⌘O: attach a file or folder to the request.
    private func pickAttachment() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Attach a file or folder to your request"
        NSApp.activate()
        let ok = panel.runModal() == .OK
        if ok, let url = panel.url { palette.model.attachment = url.path }
        palette.show(anchor: nil)
    }

    @objc private func runMacro(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        palette.show(anchor: nil)
        palette.model.query = name
        palette.model.submit()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Muon Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: URL scheme  muon://show  |  muon://ask?q=...

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, with reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: raw) else { return }
        switch url.host() {
        case "show":
            palette.show(anchor: nil)
        case "settings":
            openSettings()
        case "listen":
            talk()
        case "ask":
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
            palette.show(anchor: nil)
            palette.model.query = q
            if !q.isEmpty { palette.model.submit() }
        default:
            break
        }
    }

    @objc private func unloadModel() { LMStudioTier.unloadAll() }
    @objc private func stopToolServer() { MCPClient.shared.stop() }

    // MARK: Agent wiring

    private func wireAgent() {
        let m = palette.model
        m.handler = { [weak self] q in await self?.handle(q) }
        palette.onShow = { [weak self] in
            self?.refreshProactive()
            if Settings.voiceAutoListen { Task { await Voice.shared.start() } }
        }
        palette.onHide = { Voice.shared.cancel(); Speaker.stop() }
        m.onAttach = { [weak self] in self?.pickAttachment() }
        m.onListen = { Voice.shared.toggle() }
        Voice.shared.onText = { text in m.query = text }
        Voice.shared.onFinish = { text in
            guard !text.isEmpty else { return }
            m.query = text; m.spoken = true; m.submit()
        }
        ScreenshotWatcher.shared.apply()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { await Rules.runDue(agent: Agent.shared) }
        }
        Task { await Rules.runDue(agent: Agent.shared) }
        m.onCopy = { text in TextTools.copy(text); Sound.play(.success) }
        m.onPaste = { [weak self] text in self?.palette.pasteIntoPreviousApp(text) }
        m.canPaste = AXIsProcessTrusted()
    }

    private func handle(_ q: String) async {
        let m = palette.model
        let lower = q.lowercased()
        if lower.hasPrefix("save macro ") {
            m.answer = Agent.shared.saveMacro(named: String(q.dropFirst(11)).trimmingCharacters(in: .whitespaces))
            return
        }
        if q.count <= 200, !q.contains("\n") { Agent.shared.memory?.bump(kind: "query", name: q) }
        let spoken = m.spoken
        let started = Date()
        let out = await Agent.shared.run(q, approver: palette) { s in Task { @MainActor in m.status = s } }
        m.status = nil
        m.answer = out.cancelled ? "Cancelled." : out.answer
        m.result = out.result
        if spoken, Settings.speakReplies, !out.cancelled, let say = out.answer ?? out.result?.text { Speaker.speak(say) }
        m.canPaste = AXIsProcessTrusted()
        m.note = out.note
        if out.cancelled { Sound.play(.cancel) }
        else if out.results.contains(where: { !$0.ok }) { Sound.play(.error) }
        else if !out.results.isEmpty || !out.suggestions.isEmpty || out.result != nil { Sound.play(.success) }
        let secs = Date().timeIntervalSince(started)
        let time = secs < 1 ? "\(Int(secs * 1000)) ms" : String(format: "%.1f s", secs)
        let source = out.model ?? (out.tier == 0 ? "from memory" : out.tier == 1 ? "on-device" : "local model")
        m.footer = "\(source) · \(time)"
        m.rows = out.suggestions.map { s in
            PaletteModel.Row(icon: s.icon, title: s.title, subtitle: s.subtitle, section: s.section) { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    m.isBusy = true
                    let r = await Agent.shared.runSuggestion(s, approver: self.palette) { st in Task { @MainActor in m.status = st } }
                    m.status = nil
                    m.isBusy = false
                    m.answer = r.text
                    Sound.play(r.ok ? .success : .error)
                    if r.ok, Self.closesPalette(r.tool) { self.dismissSoon() }
                }
            }
        }
        m.selection = 0
        if !out.cancelled, out.suggestions.isEmpty, !out.results.isEmpty, out.results.allSatisfy(\.ok),
           out.results.contains(where: { Self.closesPalette($0.tool) }) {
            dismissSoon()
        }
    }

    /// "For you" rows: cached instantly, refreshed in the background at most once a day.
    private func refreshProactive() {
        let m = palette.model
        func rows(_ s: [ProactiveSuggestion]) -> [PaletteModel.Row] {
            s.map { sug in
                PaletteModel.Row(icon: sug.icon, title: sug.title, subtitle: sug.subtitle, section: "For you") { [weak self] in
                    guard let self else { return }
                    switch sug.action {
                    case .query(let q): m.query = q; m.submit()
                    case .rule(let q): m.query = "every monday " + q; m.submit()
                    case .undo: m.query = "undo"; m.submit()
                    }
                }
            }
        }
        // Recent requests (by frecency) after the suggestions; ↑/↓ walk them, ⇥ edits, ↩ runs. First run: how to get started.
        func recents() -> [PaletteModel.Row] {
            let memory = Agent.shared.memory
            m.history = memory?.top(kind: "query", n: 30) ?? []
            let recent = Array(m.history.prefix(6))
            if recent.isEmpty {
                return [PaletteModel.Row(icon: "questionmark.circle", title: "What can I ask?", subtitle: "Everything Muon can do, with examples", section: "Get started", fill: "what can you do") { m.query = "what can you do"; m.submit() }]
            }
            return recent.map { q in PaletteModel.Row(icon: "clock.arrow.circlepath", title: Attachment.displayTitle(forRequest: q), subtitle: nil, section: "Recent", fill: q) { m.query = q; m.submit() } }
        }
        if let cached = Proactive.cached() { m.idleRows = rows(cached) + recents(); return }
        m.idleRows = rows(Proactive.clipboardSuggestions() + Proactive.undoSuggestion()) + recents()
        Task.detached(priority: .utility) {
            let fresh = await Proactive.refresh(memory: Agent.shared.memory)
            await MainActor.run { m.idleRows = rows(fresh) + recents() }
        }
    }

    private static func closesPalette(_ tool: String) -> Bool {
        ["openApplication", "openPath", "revealInFinder", "quitApplication"].contains(tool)
    }

    private func dismissSoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            palette.hide()
            palette.model.reset()
        }
    }
}
