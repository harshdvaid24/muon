import AppKit
import Carbon
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Explicit entry point: without a MainMenu nib, NSApplicationMain would never instantiate the delegate.
    static func main() {
        signal(SIGPIPE, SIG_IGN) // a dead tool-server pipe must never kill the app
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        _ = CLI.runIfRequested()
        app.run()
    }

    private var statusItem: NSStatusItem!
    let palette = PanelController()
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:with:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || CLI.active { return }
        wireAgent()
        setupStatusItem()
        hotKey = HotKey(keyCode: 49 /* space */, modifiers: HotKey.controlOption) { [weak self] in
            self?.palette.toggle(anchor: nil)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "MacAgent")
        image?.isTemplate = true
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
        let ask = NSMenuItem(title: "Ask MacAgent…   ⌃⌥Space", action: #selector(openPalette), keyEquivalent: "")
        ask.target = self
        menu.addItem(ask)
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
        let quit = NSMenuItem(title: "Quit MacAgent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPalette() { palette.show(anchor: nil) }

    @objc private func runMacro(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        palette.show(anchor: nil)
        palette.model.query = name
        palette.model.submit()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "MacAgent Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: URL scheme  macagent://show  |  macagent://ask?q=...

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, with reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: raw) else { return }
        switch url.host() {
        case "show":
            palette.show(anchor: nil)
        case "settings":
            openSettings()
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
    }

    private func handle(_ q: String) async {
        let m = palette.model
        let lower = q.lowercased()
        if lower.hasPrefix("save macro ") {
            m.answer = Agent.shared.saveMacro(named: String(q.dropFirst(11)).trimmingCharacters(in: .whitespaces))
            return
        }
        let out = await Agent.shared.run(q, approver: palette) { s in Task { @MainActor in m.status = s } }
        m.status = nil
        m.answer = out.cancelled ? "Cancelled." : out.answer
        if let note = out.note { m.answer = (m.answer.map { $0 + "\n\n" } ?? "") + note }
        m.rows = out.suggestions.map { s in
            PaletteModel.Row(icon: s.icon, title: s.title, subtitle: s.subtitle) { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    m.isBusy = true
                    let r = await Agent.shared.runSuggestion(s, approver: self.palette) { st in Task { @MainActor in m.status = st } }
                    m.status = nil
                    m.isBusy = false
                    m.answer = r.text
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
