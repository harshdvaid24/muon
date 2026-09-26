import SwiftUI

@MainActor
final class PaletteModel: ObservableObject {
    struct Row: Identifiable {
        let id = UUID()
        var icon: String
        var title: String
        var subtitle: String?
        var action: (() -> Void)?
    }

    typealias Decision = ApprovalDecision

    struct Pending: Identifiable {
        let id = UUID()
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
    @Published var status: String?
    @Published var pending: Pending?
    @Published var isBusy = false
    @Published var focusRequest = 0

    /// Set by the agent wiring. Receives the submitted query.
    var handler: (String) async -> Void = { _ in }

    func submit() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isBusy else { return }
        if !rows.isEmpty, let action = rows[safe: selection]?.action, q == lastSubmitted {
            action(); return
        }
        lastSubmitted = q
        rows = []; answer = nil; selection = 0
        isBusy = true
        Task { await handler(q); isBusy = false }
    }

    func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selection = (selection + delta + rows.count) % rows.count
    }

    func activateSelection() { rows[safe: selection]?.action?() }

    func reset() { query = ""; lastSubmitted = ""; rows = []; answer = nil; status = nil; pending = nil; selection = 0 }

    private var lastSubmitted = ""
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
