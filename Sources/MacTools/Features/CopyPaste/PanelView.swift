import SwiftUI
import AppKit

/// A blurred window background that always renders "active" (so it never degrades to a
/// flat grey when the panel isn't the key window) and automatically follows the system
/// light/dark appearance via `NSVisualEffectView`.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .windowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active            // force vibrancy regardless of key-window status
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.state = .active
    }
}

struct PanelView: View {
    @ObservedObject var model: PickerModel
    @ObservedObject var store: TabStore
    let config: CopyPasteConfig
    @FocusState private var searchFocused: Bool
    @FocusState private var editFocused: Bool
    @FocusState private var labelFocused: Bool
    @FocusState private var tabNameFocused: Bool
    @FocusState private var confirmDeleteFocused: Bool

    init(model: PickerModel, config: CopyPasteConfig) {
        self.model = model
        self.store = model.store
        self.config = config
    }

    var body: some View {
        VStack(spacing: 0) {
            ClipboardBufferView(store: store)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            Divider()
            tabBar
            Divider()
            if model.searchActive {
                searchField
                Divider()
            }
            listBody
            Divider()
            if config.ui.showFooterHints { footer }
        }
        .frame(width: config.window.width, height: config.window.height)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { if model.copyToTabForIndex != nil { copyToTabOverlay } }
        .overlay { if model.labelingIndex != nil { labelOverlay } }
        .overlay { if model.namingTab { tabNameOverlay } }
        .overlay { if model.confirmDeleteTabIndex != nil { confirmDeleteOverlay } }
        .onChange(of: model.searchActive) { active in searchFocused = active }
        .onChange(of: model.query) { _ in model.selectSingle(0) }
        .onChange(of: model.editingIndex) { idx in editFocused = (idx != nil) }
        .onChange(of: model.labelingIndex) { idx in labelFocused = (idx != nil) }
        .onChange(of: model.namingTab) { active in tabNameFocused = active }
        .onChange(of: model.confirmDeleteTabIndex) { idx in confirmDeleteFocused = (idx != nil) }
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(store.tabs.enumerated()), id: \.element.id) { index, tab in
                Text(tab.name)
                    .font(.caption).bold()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(index == store.currentTab ? Color.accentColor.opacity(0.3) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { store.currentTab = index; model.selectSingle(0) }
                    .onTapGesture(count: 2) {
                        store.currentTab = index
                        model.tabNameText = tab.name
                        model.namingTabIndex = index
                        model.namingTab = true
                    }
            }
            Spacer()
            Text("\(config.keys.prevTab.displayLabel) / \(config.keys.nextTab.displayLabel)")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    // MARK: Search

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search…", text: $model.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit {
                    if model.hasMultiSelection { model.onCommitMany(model.selectedItems) }
                    else { model.commit() }
                }
        }
        .padding(10)
    }

    // MARK: List

    private var listBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.filtered.isEmpty {
                        Text(store.currentItems.isEmpty ? "Empty." : "No matches.")
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(model.filtered.enumerated()), id: \.offset) { index, item in
                        row(index: index, item: item)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if NSEvent.modifierFlags.contains(.shift) {
                                    model.selection = index
                                    model.selectRangeToAnchor()
                                } else {
                                    model.selectSingle(index)
                                    if model.editingIndex == nil { model.commit() }
                                }
                            }
                    }
                }
            }
            .onChange(of: model.selection) { sel in
                withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(sel, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func row(index: Int, item: ClipItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1).")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)

            thumbnail(for: item)

            VStack(alignment: .leading, spacing: 2) {
                if let label = item.label, !label.isEmpty {
                    Text(label).font(.body).bold().lineLimit(1)
                }
                if model.editingIndex == index, item.isEditableText {
                    TextField("", text: $model.editingText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($editFocused)
                        .lineLimit(1...max(1, config.ui.rowMaxLines))
                } else {
                    Text(previewText(item))
                        .lineLimit(1...max(1, config.ui.rowMaxLines))
                        .truncationMode(.tail)
                        .foregroundStyle(item.label == nil ? .primary : .secondary)
                }
            }
            Spacer(minLength: 0)

            Text(kindBadge(item.kind))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground(index: index))
    }

    private func rowBackground(index: Int) -> Color {
        if model.selectedIndices.contains(index) {
            // Cursor row is a touch stronger than other selected rows.
            let base = config.ui.selectionOpacity
            return Color.accentColor.opacity(index == model.selection ? base : base * 0.6)
        }
        guard config.ui.zebraStriping else { return Color.clear }
        return index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(config.ui.zebraOpacity)
    }

    @ViewBuilder
    private func thumbnail(for item: ClipItem) -> some View {
        if item.kind == .image, let blob = item.blobFilename, let nsImage = BlobStore.image(blob) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if item.kind == .file {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
        }
    }

    private func previewText(_ item: ClipItem) -> String {
        switch item.kind {
        case .text:  return (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case .image: return item.originalName ?? "Image"
        case .file:  return item.originalName ?? "File"
        }
    }

    private func kindBadge(_ kind: ClipItemKind) -> String {
        switch kind {
        case .text: return "TXT"
        case .image: return "IMG"
        case .file: return "FILE"
        }
    }

    // MARK: Overlays

    private var labelOverlay: some View {
        overlayCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Label").font(.headline)
                TextField("Enter a label…", text: $model.labelText)
                    .textFieldStyle(.roundedBorder)
                    .focused($labelFocused)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            labelFocused = true
                        }
                    }
                Text("Enter to save · Esc to cancel").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var tabNameOverlay: some View {
        overlayCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.namingTabIndex == nil ? "New Tab" : "Rename Tab").font(.headline)
                TextField("Tab name…", text: $model.tabNameText)
                    .textFieldStyle(.roundedBorder)
                    .focused($tabNameFocused)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            tabNameFocused = true
                        }
                    }
                Text("Enter to save · Esc to cancel").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var confirmDeleteOverlay: some View {
        overlayCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Delete Tab").font(.headline)
                if let idx = model.confirmDeleteTabIndex, store.tabs.indices.contains(idx) {
                    Text("“\(store.tabs[idx].name)” has \(store.tabs[idx].items.count) item(s).")
                        .font(.callout)
                }
                Text("Type “\(config.deleteTabConfirmWord)” to confirm.").font(.callout).foregroundStyle(.secondary)
                TextField(config.deleteTabConfirmWord, text: $model.confirmDeleteText)
                    .textFieldStyle(.roundedBorder)
                    .focused($confirmDeleteFocused)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            confirmDeleteFocused = true
                        }
                    }
                Text("Enter to confirm · Esc to cancel").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var copyToTabOverlay: some View {
        overlayCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Copy to tab").font(.headline)
                ForEach(Array(store.tabs.enumerated()), id: \.element.id) { index, tab in
                    if index != store.currentTab {
                        Text("\(index + 1). \(tab.name)")
                            .padding(.vertical, 2)
                    }
                }
                Text("Press the tab number · Esc to cancel")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func overlayCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            content()
                .padding(18)
                .frame(width: 320)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 20)
        }
    }

    // MARK: Footer

    private var footer: some View {
        let k = config.keys
        return HStack(spacing: 10) {
            Text("\(k.selectUp.displayLabel)\(k.selectDown.displayLabel) select").hint()
            Text("⇧ multi").hint()
            Text("\(k.moveUp.displayLabel)\(k.moveDown.displayLabel) reorder").hint()
            Text("\(k.commit.displayLabel) paste").hint()
            Text("\(config.search.displayLabel) find").hint()
            Text("\(k.editText.displayLabel) edit").hint()
            Text("\(k.copyToTab.displayLabel)→tab").hint()
            Text("\(k.label.displayLabel) label").hint()
            Text("\(k.delete.displayLabel) del").hint()
            Spacer()
            if model.hasMultiSelection {
                Text("\(model.selectedIndices.count) selected").foregroundStyle(.secondary)
            } else {
                Text("\(model.filtered.count)").foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

private extension View {
    func hint() -> some View { self.foregroundStyle(.secondary) }
}

/// The "currently in the paste buffer" line, shown in the window's title-bar strip.
struct ClipboardBufferView: View {
    @ObservedObject var store: TabStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(store.currentClipboardSummary.isEmpty ? "—" : store.currentClipboardSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(store.currentClipboardSummary)
    }
}
