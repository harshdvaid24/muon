import AppKit
import Carbon
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Explicit entry point: without a MainMenu nib, NSApplicationMain would never instantiate the delegate.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var statusItem: NSStatusItem!
    let palette = PanelController()
    private var hotKey: HotKey?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:with:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        installDemoHandler() // TEMP: replaced by Agent wiring in Task 8
        NSLog("MacAgent: didFinishLaunching, status button=%@", String(describing: statusItem?.button))
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
        let ask = NSMenuItem(title: "Ask MacAgent…", action: #selector(openPalette), keyEquivalent: "")
        ask.target = self
        menu.addItem(ask)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MacAgent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPalette() { palette.show(anchor: nil) }

    // MARK: URL scheme  macagent://show  |  macagent://ask?q=...

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, with reply: NSAppleEventDescriptor) {
        NSLog("MacAgent: GetURL %@", event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue ?? "nil")
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: raw) else { return }
        switch url.host() {
        case "show":
            palette.show(anchor: nil)
        case "ask":
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
            palette.show(anchor: nil)
            palette.model.query = q
            if !q.isEmpty { palette.model.submit() }
        default:
            break
        }
    }

    // TEMP demo wiring for visual verification of Task 5. Removed in Task 8.
    private func installDemoHandler() {
        let m = palette.model
        m.handler = { q in
            m.status = "Thinking…"
            try? await Task.sleep(for: .milliseconds(400))
            m.status = nil
            if q.lowercased().hasPrefix("demo confirm") {
                m.pending = .init(title: "Move 3 screenshots to ~/Downloads/Archive",
                                  detail: "Screenshot 2026-09-01.png\nScreenshot 2026-09-02.png\nScreenshot 2026-09-03.png",
                                  destructive: false, allowAlwaysLabel: "Always allow in Downloads") { d in
                    m.pending = nil; m.answer = "Decision: \(d)"
                }
                return
            }
            m.rows = [
                .init(icon: "folder", title: "Open ~/Work/kathak in Visual Studio Code", subtitle: "openPath", action: { m.answer = "opened" }),
                .init(icon: "hammer", title: "Open ~/Work/kathak in Xcode", subtitle: nil, action: nil),
                .init(icon: "magnifyingglass", title: "Reveal ~/Work/kathak in Finder", subtitle: nil, action: nil),
            ]
        }
    }
}
