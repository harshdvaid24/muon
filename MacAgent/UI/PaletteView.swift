import SwiftUI

struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    var onClose: () -> Void
    var onSize: (CGSize) -> Void
    @FocusState private var focused: Bool
    @Namespace private var glassNS

    private var hasBody: Bool { !model.rows.isEmpty || model.answer != nil || model.status != nil || model.pending != nil }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 0) {
                searchBar
                if hasBody {
                    Divider().padding(.horizontal, 16)
                    if let status = model.status { statusRow(status) }
                    if let pending = model.pending { ConfirmCard(pending: pending) }
                    if let answer = model.answer { answerBlock(answer) }
                    if !model.rows.isEmpty { results }
                }
            }
            .frame(width: 640)
            .fixedSize(horizontal: false, vertical: true)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .glassEffectID("palette", in: glassNS)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .onExitCommand { onClose() }
        .onAppear { focused = true }
        .onChange(of: model.focusRequest) { focused = true }
        .animation(.smooth(duration: 0.25), value: hasBody)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            TextField("Ask MacAgent…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($focused)
                .onSubmit { model.submit() }
                .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
            if model.isBusy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 22)
        .frame(height: 60)
    }

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dotted").foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
    }

    private func answerBlock(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 280)
        .padding(.horizontal, 22).padding(.vertical, 12)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    Image(systemName: row.icon)
                        .frame(width: 22)
                        .foregroundStyle(index == model.selection ? .primary : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title).lineLimit(1)
                        if let s = row.subtitle { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer()
                    if index == model.selection, row.action != nil { Image(systemName: "return").foregroundStyle(.tertiary) }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(index == model.selection ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10))
                .contentShape(.rect)
                .onTapGesture { model.selection = index; model.activateSelection() }
            }
        }
        .padding(10)
    }
}

struct ConfirmCard: View {
    let pending: PaletteModel.Pending

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(pending.title, systemImage: pending.destructive ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                .font(.headline)
            Text(pending.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                if let label = pending.allowAlwaysLabel {
                    Button(label) { pending.decide(.allowAlways) }.buttonStyle(.glass)
                }
                Spacer()
                Button("Cancel") { pending.decide(.cancel) }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button(pending.destructive ? "Proceed" : "Allow") { pending.decide(.allow) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
    }
}
