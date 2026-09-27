import SwiftUI

@MainActor
final class PaletteModel: ObservableObject {
    struct Row: Identifiable {
        let id = UUID()
        var icon: String
        var title: String
        var subtitle: String?
        var section: String?
        var action: (() -> Void)?
    }

    typealias Decision = ApprovalDecision

    struct Pending: Identifiable {
        let id = UUID()
        var icon: String
        var title: String
        var detail: String
        var destructive: Bool
        var allowAlwaysLabel: String?
        var decide: (Decision) -> Void
    }

    @Published var query = ""
    @Published var rows: [Row] = []
    @Published var selection = 0
    @Published var answer: String?
    @Published var result: TextResult?
    @Published var note: String?
    @Published var footer: String?
    @Published var status: String?
    @Published var pending: Pending?
    @Published var isBusy = false
    @Published var focusRequest = 0
    /// Shown while the query is empty: what Muon noticed for you.
    @Published var idleRows: [Row] = []

    /// Set by the agent wiring. Receives the submitted query.
    var handler: (String) async -> Void = { _ in }

    /// Return key: on a confirm card it means Allow; otherwise it runs the query.
    func handleReturn() {
        if let p = pending { p.decide(.allow); return }
        submit()
    }

    /// Programmatic submit (URL scheme, macros, intents): never resolves a pending card as Allow.
    func submit() {
        pending?.decide(.cancel)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if isBusy { queued = q; return }   // run it as soon as the current request finishes
        if !rows.isEmpty, let action = rows[safe: selection]?.action, q == lastSubmitted {
            action(); return
        }
        lastSubmitted = q
        rows = []; answer = nil; result = nil; note = nil; footer = nil; selection = 0
        isBusy = true
        Task {
            await handler(q)
            isBusy = false
            if let next = queued { queued = nil; query = next; submit() }
        }
    }

    func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selection = (selection + delta + rows.count) % rows.count
    }

    func activateSelection() { rows[safe: selection]?.action?() }

    func reset() { query = ""; lastSubmitted = ""; rows = []; answer = nil; result = nil; note = nil; footer = nil; status = nil; pending = nil; selection = 0 }

    /// Set by the app: copy a result, or paste it into the app the user came from.
    var onCopy: (String) -> Void = { _ in }
    var onPaste: (String) -> Void = { _ in }
    var canPaste = false

    /// Esc: cancel a pending card first; only close when nothing is pending.
    func escape() -> Bool {
        if let p = pending { p.decide(.cancel); return false }
        return true
    }

    private var lastSubmitted = ""
    private var queued: String?
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
