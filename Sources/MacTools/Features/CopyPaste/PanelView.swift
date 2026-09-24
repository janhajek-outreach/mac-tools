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

/// Spacing/sizing of the tiles layout, shared by the view and keyboard navigation.
enum TileMetrics {
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 10
    /// Around each tile, where the selection background shows.
    static let inset: CGFloat = 4
    static let caption: CGFloat = 20

    static func columns(width: Double, tile: Double) -> Int {
        max(1, Int((CGFloat(width) - 2 * padding + spacing) / (CGFloat(tile) + 2 * inset + spacing)))
    }

    /// Rows that fit in the list area (window minus the clipboard line, tab bar and footer).
    static func rowsPerPage(height: Double, tile: Double) -> Int {
        max(1, Int((CGFloat(height) - 150) / (CGFloat(tile) + 2 * inset + caption + spacing)))
    }
}

/// GIF thumbnail that animates according to `ui.animateGifs` (the view itself also checks
/// that it's actually visible before playing).
private struct GIFThumbnailCell: View {
    let source: URL
    let mode: String
    let windowVisible: Bool
    let isSelected: Bool

    private var allowed: Bool {
        guard windowVisible else { return false }
        switch mode {
        case "off": return false
        case "selected": return isSelected
        default: return true
        }
    }

    var body: some View {
        AnimatedGIFView(source: source, allowed: allowed)
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
            if store.layout(ofTab: store.currentTab) == .tiles { tileBody } else { listBody }
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
        .overlay { if model.pendingCopy != nil { confirmCopyOverlay } }
        .overlay { if model.pendingDownload != nil { confirmDownloadOverlay } }
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
                .onAppear {
                    // The field is inserted into the hierarchy in the same update that flips
                    // `searchActive`, so focus it once it actually exists.
                    searchFocused = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        searchFocused = true
                    }
                }
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

    // MARK: Tiles

    private var tileBody: some View {
        let size = CGFloat(config.ui.tileSize)
        let columns = Array(repeating: GridItem(.fixed(size + 2 * TileMetrics.inset), spacing: TileMetrics.spacing),
                            count: model.columns)
        return ScrollViewReader { proxy in
            ScrollView {
                if model.filtered.isEmpty {
                    Text(store.currentItems.isEmpty ? "Empty." : "No matches.")
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: TileMetrics.spacing) {
                    ForEach(Array(model.filtered.enumerated()), id: \.offset) { index, item in
                        tile(index: index, item: item, size: size)
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
                .padding(TileMetrics.padding)
            }
            .onChange(of: model.selection) { sel in
                withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(sel, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func tile(index: Int, item: ClipItem, size: CGFloat) -> some View {
        let selected = model.selectedIndices.contains(index)
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                tileContent(item: item, index: index, size: size)
                    .frame(width: size, height: size)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                statusIcon(for: item)
                    .padding(5)
            }
            if model.editingIndex == index {
                TextField("", text: $model.editingText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($editFocused)
                    .onAppear {
                        editFocused = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { editFocused = true }
                    }
            } else {
                Text(tileCaption(item))
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(item.label == nil ? .secondary : .primary)
                    .frame(width: size)
            }
        }
        .frame(width: size)
        .padding(TileMetrics.inset)
        .opacity(store.isMissing(item) ? 0.4 : 1)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(index == model.selection
                                                           ? config.ui.selectionOpacity
                                                           : config.ui.selectionOpacity * 0.6)
                               : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(index == model.selection ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    @ViewBuilder
    private func tileContent(item: ClipItem, index: Int, size: CGFloat) -> some View {
        if item.kind == .text {
            Text((item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.caption)
                .lineLimit(Int(size / 15))
                .padding(8)
                .frame(width: size, height: size, alignment: .topLeading)
        } else {
            thumbnail(for: item, index: index, size: size)
        }
    }

    /// Label if set, else the image/file name, else the first line of text.
    private func tileCaption(_ item: ClipItem) -> String {
        if let label = item.label, !label.isEmpty { return label }
        if item.kind == .text {
            return (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? ""
        }
        return previewText(item)
    }

    /// Missing (⚠︎) / linked (🔗) marker shared by rows and tiles.
    @ViewBuilder
    private func statusIcon(for item: ClipItem) -> some View {
        if store.isMissing(item) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help(item.isReference
                      ? "Original file is missing — can't paste"
                      : "Stored copy is missing — can't paste")
        } else if item.isReference {
            Image(systemName: "link")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help("Linked — not stored, may go missing if the original is deleted")
        }
    }

    // MARK: List row

    @ViewBuilder
    private func row(index: Int, item: ClipItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1).")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)

            thumbnail(for: item, index: index, size: 80)

            VStack(alignment: .leading, spacing: 2) {
                if let label = item.label, !label.isEmpty {
                    Text(label).font(.body).bold().lineLimit(1)
                }
                if model.editingIndex == index {
                    TextField("", text: $model.editingText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($editFocused)
                        .lineLimit(1...max(1, item.kind == .text ? config.ui.rowMaxLines : 1))
                        .onAppear {
                            // The field is inserted into the hierarchy in the same update that
                            // sets `editingIndex`, so focus it once it actually exists.
                            editFocused = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                                editFocused = true
                            }
                        }
                } else {
                    Text(previewText(item))
                        .lineLimit(1...max(1, config.ui.rowMaxLines))
                        .truncationMode(.tail)
                        .foregroundStyle(item.label == nil ? .primary : .secondary)
                }
            }
            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(kindBadge(item.kind))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                statusIcon(for: item)
            }
            .padding(.top, 3)
        }
        .opacity(store.isMissing(item) ? 0.4 : 1)
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

    /// Image/GIF thumbnail (or a placeholder / file icon) at `size` points — 80 in the list,
    /// `ui.tileSize` in tiles. Thumbnails are decoded at 2x of that.
    @ViewBuilder
    private func thumbnail(for item: ClipItem, index: Int, size: CGFloat) -> some View {
        let url = item.kind == .image && !store.isMissing(item) ? store.contentURL(for: item, inTab: store.currentTab) : nil
        let pixels = Int(size * 2)
        if let url, BlobStore.isGIF(url) {
            GIFThumbnailCell(
                source: url,
                mode: config.ui.animateGifs,
                windowVisible: model.isVisible,
                isSelected: index == model.selection
            )
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let url, let nsImage = BlobStore.thumbnail(at: url, maxPixelSize: pixels) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if item.kind == .image {
            Image(systemName: "photo")
                .font(size > 100 ? .largeTitle : .title2)
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        } else if item.kind == .file {
            Image(systemName: "doc.fill")
                .font(size > 100 ? .system(size: 48) : .title2)
                .foregroundStyle(store.isMissing(item) ? Color.secondary : Color.blue)
                .frame(width: size > 100 ? size : 40, height: size > 100 ? size : 40)
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

    private var confirmCopyOverlay: some View {
        overlayCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Copy to \(model.pendingCopy?.destName ?? "tab")").font(.headline)
                if let p = model.pendingCopy {
                    let size = FileReference.formatBytes(p.bytes)
                    Text(p.itemCount == 1
                         ? "Putting this item in “\(p.destName)” will create a copy with size \(size)."
                         : "Putting these items in “\(p.destName)” will create copies of \(p.itemCount) linked files, \(size) in total.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if let free = p.freeBytes {
                        Text("Free space: \(FileReference.formatBytes(free))")
                            .font(.callout)
                            .foregroundStyle(p.hasEnoughSpace ? Color.secondary : Color.red)
                    }
                    if !p.hasEnoughSpace {
                        Text("Not enough free space.").font(.callout).bold().foregroundStyle(.red)
                        Text("Esc to cancel").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Enter to copy · Esc to cancel").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var confirmDownloadOverlay: some View {
        overlayCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Download large image?").font(.headline)
                if let p = model.pendingDownload {
                    let limit = FileReference.formatBytes(p.limitBytes)
                    if p.candidates.count == 1, let c = p.candidates.first {
                        Text(c.url.lastPathComponent).font(.callout).bold().lineLimit(1).truncationMode(.middle)
                        Text(c.size.map { "It's \(FileReference.formatBytes($0)) — over the \(limit) download limit." }
                             ?? "It's over the \(limit) download limit.")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("\(p.candidates.count) images are over the \(limit) download limit"
                             + (p.knownBytes > 0 ? " (\(FileReference.formatBytes(p.knownBytes))\(p.hasUnknownSize ? "+" : "") in total)." : "."))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Enter to download · Esc to skip").font(.caption).foregroundStyle(.secondary)
                }
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
            Text("\(k.downloadImage.displayLabel) img").hint()
            Text("\(k.toggleLayout.displayLabel) \(store.layout(ofTab: store.currentTab) == .tiles ? "list" : "tiles")").hint()
            Text("\(k.label.displayLabel) label").hint()
            Text("\(k.delete.displayLabel) del").hint()
            Spacer()
            if let message = model.statusMessage {
                Text(message).foregroundStyle(.orange)
            } else if !model.hasMultiSelection, let item = model.selectedItem, store.isMissing(item) {
                Text("File is missing — can't paste").foregroundStyle(.orange)
            } else if model.hasMultiSelection {
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
