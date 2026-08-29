import SwiftUI
import Combine

/// Shared UI state for the picker, driven by keyboard events from the window controller.
final class PickerModel: ObservableObject {
    @Published var query: String = ""
    @Published var selection: Int = 0
    @Published var searchActive: Bool = false

    let history: HistoryStore
    var onCommit: (String) -> Void = { _ in }
    var onCancel: () -> Void = {}

    init(history: HistoryStore) {
        self.history = history
    }

    var filtered: [String] {
        guard !query.isEmpty else { return history.items }
        return history.items.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    func reset() {
        query = ""
        selection = 0
        searchActive = false
    }

    func moveUp() {
        guard !filtered.isEmpty else { return }
        selection = max(0, selection - 1)
    }

    func moveDown() {
        guard !filtered.isEmpty else { return }
        selection = min(filtered.count - 1, selection + 1)
    }

    func commit() {
        guard filtered.indices.contains(selection) else { return }
        onCommit(filtered[selection])
    }

    func activateSearch() {
        searchActive = true
    }

    func escape() {
        if searchActive && !query.isEmpty {
            query = ""
            selection = 0
        } else if searchActive {
            searchActive = false
            query = ""
            selection = 0
        } else {
            onCancel()
        }
    }
}

struct PanelView: View {
    @ObservedObject var model: PickerModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if model.searchActive {
                searchField
                Divider()
            }
            listBody
            Divider()
            footer
        }
        .frame(width: 480, height: 360)
        .onChange(of: model.searchActive) { active in
            searchFocused = active
        }
        .onChange(of: model.query) { _ in
            model.selection = 0
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search…", text: $model.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { model.commit() }
        }
        .padding(10)
    }

    private var listBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.filtered.isEmpty {
                        Text(model.history.items.isEmpty ? "No clipboard history yet." : "No matches.")
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(model.filtered.enumerated()), id: \.offset) { index, item in
                        row(index: index, item: item)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selection = index
                                model.commit()
                            }
                    }
                }
            }
            .onChange(of: model.selection) { sel in
                withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(sel, anchor: .center) }
            }
        }
    }

    private func row(index: Int, item: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1).")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            Text(item.trimmingCharacters(in: .whitespacesAndNewlines))
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(index == model.selection ? Color.accentColor.opacity(0.25) : Color.clear)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("Navigate", systemImage: "arrow.up.arrow.down")
            Label("Paste", systemImage: "return")
            Label("Search", systemImage: "magnifyingglass")
            Spacer()
            Text("\(model.filtered.count)")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
