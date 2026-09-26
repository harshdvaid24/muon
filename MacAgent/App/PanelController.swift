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
        var y: CGFloat
        if let a = anchor {
            x = a.midX - Self.width / 2
            y = a.minY - 6
        } else {
            x = vf.midX - Self.width / 2
            y = vf.maxY - vf.height * 0.18
        }
        x = min(max(x, vf.minX + 8), vf.maxX - Self.width - 8)
        topLeft = NSPoint(x: x, y: y)
        panel.setFrameTopLeftPoint(topLeft)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        model.focusRequest += 1
    }

    func hide() {
        model.pending?.decide(.cancel)
        panel.orderOut(nil)
    }

    private func resize(to size: CGSize) {
        guard size.height > 0 else { return }
        panel.setContentSize(NSSize(width: Self.width, height: size.height))
        panel.setFrameTopLeftPoint(topLeft)
    }

    func windowDidResignKey(_ notification: Notification) { hide() }
}

extension PanelController: Approver {
    func approve(_ a: PendingAction) async -> ApprovalDecision {
        if a.destructive {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = a.title
            alert.informativeText = a.detail
            alert.addButton(withTitle: "Proceed")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn ? .allow : .cancel
        }
        return await withCheckedContinuation { cont in
            model.pending?.decide(.cancel) // a newer request supersedes any card still waiting
            var done = false
            model.pending = PaletteModel.Pending(title: a.title, detail: a.detail, destructive: false, allowAlwaysLabel: a.alwaysLabel) { [weak self] d in
                guard !done else { return }
                done = true
                self?.model.pending = nil
                cont.resume(returning: d)
            }
            if !panel.isVisible { show(anchor: nil) }
        }
    }
}
