import SwiftUI
import UniformTypeIdentifiers

struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    @ObservedObject private var voice = Voice.shared
    @State private var dropping = false
    var onClose: () -> Void
    var onSize: (CGSize) -> Void
    @FocusState private var focused: Bool
    @Namespace private var glassNS

    private var hasBody: Bool { !model.rows.isEmpty || model.answer != nil || model.result != nil || model.status != nil || model.pending != nil || model.note != nil || model.showsIdle || voice.problem != nil }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 0) {
                searchBar
                if hasBody {
                    Divider().padding(.horizontal, 16)
                    if let status = model.status { statusRow(status) }
                    if let pending = model.pending { ConfirmCard(pending: pending) }
                    if let result = model.result { resultBlock(result) }
                    if let answer = model.answer { answerBlock(answer) }
                    if !model.rows.isEmpty { results }
                    if model.showsIdle { idleList }
                    if let note = model.note { noteRow(note) }
                    if let problem = voice.problem { noteRow(problem) }
                    if let footer = model.footer, model.pending == nil, model.status == nil { footerRow(footer) }
                }
            }
            .frame(width: 640)
            .fixedSize(horizontal: false, vertical: true)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .glassEffectID("palette", in: glassNS)
            .overlay {
                if dropping {
                    RoundedRectangle(cornerRadius: 26).strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { handleDrop($0) }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .onExitCommand { if model.escape() { onClose() } }
        .onAppear { focused = true }
        .onChange(of: model.focusRequest) { focused = true }
        .animation(.smooth(duration: 0.22), value: hasBody)
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(.secondary)
            if let a = model.attachment { attachmentChip(a) }
            TextField(voice.isListening ? "Listening…" : "Ask Muon…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($focused)
                .onSubmit { model.handleReturn() }
                .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
                .onKeyPress(.tab) { model.editSelection() ? .handled : .ignored }
                .onKeyPress(phases: .down) { shortcut($0) }
            if model.isBusy {
                ProgressView().controlSize(.small)
            } else if model.pending == nil {
                attachButton
                micButton
                KeyHint(model.query.isEmpty && model.attachment == nil ? "esc" : "↩")
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    /// ⌘O attach · ⌘⇧M talk · ⌘V with an image or file on the clipboard attaches it (text pastes as usual).
    private func shortcut(_ press: KeyPress) -> KeyPress.Result {
        let k = press.characters.lowercased()
        if press.modifiers == .command, k == "o" { model.onAttach(); return .handled }
        if press.modifiers == [.command, .shift], k == "m" { model.onListen(); return .handled }
        if press.modifiers == .command, k == "v" {
            if let p = Attachment.fromPasteboard() { model.attachment = p } else { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
            return .handled
        }
        return .ignored
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        p.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { model.attachment = url.path; model.focusRequest += 1 }
        }
        return true
    }

    private var attachButton: some View {
        Button { model.onAttach() } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(model.attachment == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Attach a file or folder (⌘O), or drop one here")
    }

    private var micButton: some View {
        Button { model.onListen() } label: {
            Image(systemName: voice.isListening ? "waveform" : "mic")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(voice.isListening ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .symbolEffect(.variableColor.iterative, isActive: voice.isListening)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Talk to Muon (⌘⇧M)")
    }

    private func attachmentChip(_ path: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: Attachment.icon(for: path)).font(.system(size: 12, weight: .medium))
            Text((path as NSString).lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle).frame(maxWidth: 170)
            Button { model.attachment = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .help("Remove attachment")
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .foregroundStyle(.tint)
        .background(.tint.opacity(0.16), in: .capsule)
        .transition(.scale.combined(with: .opacity))
    }

    private func sectionHeader(_ section: String, first: Bool) -> some View {
        Text(section.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.top, first ? 8 : 10).padding(.bottom, 4)
    }

    // MARK: Body blocks

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
    }

    private func answerBlock(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12.5, design: .monospaced))
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 280)
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 14)
    }

    private func resultBlock(_ r: TextResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(r.label).font(.system(size: 13, weight: .semibold))
                Text(r.source).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(.primary.opacity(0.08), in: .rect(cornerRadius: 6))
                Spacer()
            }
            ScrollView {
                Text(r.text)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            HStack(spacing: 8) {
                Spacer()
                if model.canPaste {
                    Button { model.onCopy(r.text) } label: { HStack(spacing: 6) { Image(systemName: "doc.on.doc"); Text("Copy") } }
                        .buttonStyle(.glass)
                    Button { model.onPaste(r.text) } label: { HStack(spacing: 6) { Image(systemName: "arrow.down.doc"); Text("Paste") } }
                        .buttonStyle(.glassProminent)
                } else {
                    Button { model.onCopy(r.text) } label: { HStack(spacing: 6) { Image(systemName: "doc.on.doc"); Text("Copy") } }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 16)
    }

    private func noteRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 1)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
    }

    private func footerRow(_ text: String) -> some View {
        HStack {
            Text(text).font(.system(size: 11)).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 22).padding(.bottom, 12)
    }

    private var idleList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.idleRows.enumerated()), id: \.element.id) { index, row in
                if let section = row.section, index == 0 || model.idleRows[index - 1].section != section {
                    sectionHeader(section, first: index == 0)
                }
                ResultRow(row: row, selected: index == model.selection)
                    .contentShape(.rect)
                    .onTapGesture { model.selection = index; row.action?() }
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 8)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                if let section = row.section, index == 0 || model.rows[index - 1].section != section {
                    sectionHeader(section, first: index == 0)
                }
                ResultRow(row: row, selected: index == model.selection)
                    .contentShape(.rect)
                    .onTapGesture { model.selection = index; model.activateSelection() }
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 8)
    }
}

private struct ResultRow: View {
    let row: PaletteModel.Row
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24)
                .background(selected ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(.primary.opacity(0.08)), in: .rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                if let s = row.subtitle { Text(s).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if selected, row.fill != nil { KeyHint("⇥ edit") }
            if selected, row.action != nil { KeyHint("↩") }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(selected ? AnyShapeStyle(.primary.opacity(0.10)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10))
    }
}

/// Small keyboard hint capsule ("esc", "↩").
struct KeyHint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.primary.opacity(0.08), in: .rect(cornerRadius: 6))
    }
}

struct ConfirmCard: View {
    let pending: PaletteModel.Pending

    private var looksLikePaths: Bool { pending.detail.contains("/") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: pending.icon)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(pending.destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                    .frame(width: 28, height: 28)
                    .background(pending.destructive ? AnyShapeStyle(.red.opacity(0.18)) : AnyShapeStyle(.tint.opacity(0.22)), in: .rect(cornerRadius: 8))
                Text(pending.title).font(.system(size: 15, weight: .semibold))
            }
            Text(pending.detail)
                .font(looksLikePaths ? .system(size: 12.5, design: .monospaced) : .system(size: 13))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if let label = pending.allowAlwaysLabel {
                    Button(label) { pending.decide(.allowAlways) }.buttonStyle(.glass)
                }
                Spacer()
                Button { pending.decide(.cancel) } label: { HStack(spacing: 6) { Text("Cancel"); Text("esc").font(.system(size: 11)).opacity(0.6) } }
                    .buttonStyle(.glass)
                Button { pending.decide(.allow) } label: { HStack(spacing: 6) { Text(pending.destructive ? "Proceed" : "Allow"); Text("↩").font(.system(size: 11)).opacity(0.75) } }
                    .buttonStyle(.glassProminent)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 18)
    }
}
