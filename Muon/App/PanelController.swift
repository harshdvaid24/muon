import AppKit
import SwiftUI

/// Borderless, transparent, floating panel hosting the Liquid Glass palette.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let model = PaletteModel()
    private var topLeft: NSPoint = .zero
    private var previousApp: NSRunningApplication?
    private var bottomAnchored = false
    private var anchorX: CGFloat = 0
    private var bottomY: CGFloat = 0
    private static let width: CGFloat = 640

    private lazy var panel: KeyPanel = {
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 64),
                         styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.delegate = self
        let root = PaletteView(model: model, onClose: { [weak self] in self?.hide() },
                               onSize: { [weak self] size in self?.resize(to: size) })
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        p.contentView = host
        return p
    }()

    var isVisible: Bool { panel.isVisible }

    func toggle(anchor: NSRect?) { isVisible ? hide() : show(anchor: anchor) }

    func show(anchor: NSRect?) {
        let screen = anchor.flatMap { a in NSScreen.screens.first { $0.frame.intersects(a) } }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        var x: CGFloat
        if let a = anchor {
            // Menu-bar click: hang the panel from just under the icon, growing downward.
            x = min(max(a.midX - Self.width / 2, vf.minX + 8), vf.maxX - Self.width - 8)
            bottomAnchored = false
            anchorX = x
            topLeft = NSPoint(x: x, y: a.minY - 6)
            panel.setFrameTopLeftPoint(topLeft)
        } else {
            // Hotkey: bottom-center, growing upward from a fixed bottom edge.
            x = vf.midX - Self.width / 2
            bottomAnchored = true
            anchorX = x
            bottomY = vf.minY + 96
            panel.setFrameOrigin(NSPoint(x: x, y: bottomY))
        }
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        model.focusRequest += 1
        Sound.play(.appear)
    }

    func hide() {
        model.pending?.decide(.cancel)
        panel.orderOut(nil)
        // If nothing else took focus (Esc, quit-app…), hand it back to the app the user came from.
        let me = ProcessInfo.processInfo.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == me {
            if let prev = previousApp, !prev.isTerminated, !prev.isHidden {   // never unhide an app the user hid
                NSApp.yieldActivation(to: prev)
                prev.activate()
            } else {
                NSApp.hide(nil)
            }
        }
    }

    private func resize(to size: CGSize) {
        guard size.height > 0 else { return }
        panel.setContentSize(NSSize(width: Self.width, height: size.height))
        if bottomAnchored {
            panel.setFrameOrigin(NSPoint(x: anchorX, y: bottomY)) // fixed bottom edge → grows upward
        } else {
            panel.setFrameTopLeftPoint(topLeft) // fixed top edge → grows downward
        }
    }

    func windowDidResignKey(_ notification: Notification) { hide() }
}

extension PanelController: Approver {
    func approve(_ a: PendingAction) async -> ApprovalDecision {
        model.status = nil
        if a.destructive {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = a.title
            alert.informativeText = a.detail
            alert.addButton(withTitle: "Cancel")   // default (Return) is the safe choice
            alert.addButton(withTitle: "Proceed")
            return alert.runModal() == .alertSecondButtonReturn ? .allow : .cancel
        }
        Sound.play(.prompt)
        return await withCheckedContinuation { cont in
            model.pending?.decide(.cancel) // a newer request supersedes any card still waiting
            var done = false
            model.pending = PaletteModel.Pending(icon: a.icon, title: a.title, detail: a.detail, destructive: false, allowAlwaysLabel: a.alwaysLabel) { [weak self] d in
                guard !done else { return }
                done = true
                self?.model.pending = nil
                cont.resume(returning: d)
            }
            if !panel.isVisible { show(anchor: nil) }
        }
    }
}
