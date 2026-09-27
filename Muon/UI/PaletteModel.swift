import SwiftUI

@MainActor
final class PaletteModel: ObservableObject {
    struct Row: Identifiable {
        let id = UUID()
        var icon: String
        var title: String
        var subtitle: String?
        var section: String?
        /// Text that ⇥ puts into the field for editing (recent requests).
        var fill: String? = nil
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
    /// Shown while the query is empty: what Muon noticed for you, then your recent requests.
    @Published var idleRows: [Row] = []
    /// A file attached by drop, ⌘O or paste; composed into the request on submit.
    @Published var attachment: String?
    /// Past requests by frecency, for ↑/↓ in the field. Set by the app when the palette opens.
    var history: [String] = []
    /// True when the request being submitted was spoken.
    var spoken = false

    /// Set by the app: pick a file (⌘O), toggle the microphone (⌘⇧M).
    var onAttach: () -> Void = {}
    var onListen: () -> Void = {}

    var showsIdle: Bool { query.isEmpty && attachment == nil && rows.isEmpty && answer == nil && result == nil && pending == nil && status == nil && !idleRows.isEmpty }

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
        if showsIdle, let action = idleRows[safe: selection]?.action { action(); return }
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = attachment.map { Attachment.compose(query: typed, path: $0) } ?? typed
        guard !q.isEmpty else { return }
        historyIndex = -1
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
            spoken = false
            if let next = queued { queued = nil; query = next; submit() }
        }
    }

    /// ↑/↓: through result rows, else the idle list, else the field cycles through recent requests (the draft is one slot).
    func moveSelection(_ delta: Int) {
        if !rows.isEmpty { selection = (selection + delta + rows.count) % rows.count; return }
        if showsIdle { selection = (selection + delta + idleRows.count) % idleRows.count; return }
        guard pending == nil, !history.isEmpty else { return }
        if historyIndex >= 0, query != history[historyIndex] { historyIndex = -1 }   // edited: that is the new draft
        if historyIndex == -1 { draft = query }
        let n = history.count + 1
        historyIndex = (((historyIndex + 1 + delta) % n) + n) % n - 1
        query = historyIndex == -1 ? draft : history[historyIndex]
    }

    /// ⇥: put the selected recent request into the field for editing. False when nothing applies.
    func editSelection() -> Bool {
        guard showsIdle, let fill = idleRows[safe: selection]?.fill else { return false }
        query = fill; historyIndex = -1
        return true
    }

    func activateSelection() { rows[safe: selection]?.action?() }

    func reset() { query = ""; lastSubmitted = ""; rows = []; answer = nil; result = nil; note = nil; footer = nil; status = nil; pending = nil; selection = 0; attachment = nil; historyIndex = -1; draft = "" }

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
    private var historyIndex = -1
    private var draft = ""
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
