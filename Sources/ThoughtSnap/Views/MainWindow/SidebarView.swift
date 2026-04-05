#if os(macOS)
import SwiftUI

// MARK: - SidebarView

/// Left column of the main window.
///
/// Sections:
///   1. Search bar — activates SearchResultsView in the timeline column
///   2. Fixed filters — All Notes, Starred, Pinned
///   3. Spaces — fetched from StorageService
///   4. Tags — all distinct tags from the tags table
struct SidebarView: View {

    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var windowVM:       MainWindowViewModel

    @State private var spaces: [Space] = []
    @State private var tags:   [String] = []
    @State private var isAddingSpace = false
    @State private var newSpaceName  = ""

    var body: some View {
        List(selection: Binding<String?>(
            get: { selectionID },
            set: { applySelection($0) }
        )) {
            // ── Search bar ──────────────────────────────────────────────
            searchBar

            // ── Fixed filters ───────────────────────────────────────────
            Section {
                filterRow(.all)
                filterRow(.starred)
                filterRow(.pinned)
            }

            // ── Spaces ──────────────────────────────────────────────────
            Section {
                ForEach(spaces) { space in
                    Label(space.name, systemImage: space.icon ?? "folder")
                        .tag("space:\(space.id.uuidString)")
                        .badge(Text(""))  // future: note count badge
                }

                // Add Space button (only shown for non-default spaces)
                Button(action: { isAddingSpace = true }) {
                    Label("New Space…", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Spaces")
            }

            // ── Tags ────────────────────────────────────────────────────
            if !tags.isEmpty {
                Section {
                    ForEach(tags, id: \.self) { tag in
                        Label("#\(tag)", systemImage: "number")
                            .tag("tag:\(tag)")
                            .foregroundStyle(
                                windowVM.selectedFilter == .tag(tag)
                                    ? Color.accentColor : Color(NSColor.labelColor)
                            )
                    }
                } header: {
                    Text("Tags")
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, maxWidth: 240)
        .onAppear { reload() }
        .sheet(isPresented: $isAddingSpace) { newSpaceSheet }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.system(size: 13))
            TextField("Search…", text: $windowVM.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !windowVM.searchQuery.isEmpty {
                Button(action: windowVM.clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .padding(.bottom, 4)
    }

    // MARK: - Filter row

    private func filterRow(_ filter: TimelineFilter) -> some View {
        Label(filter.displayName, systemImage: filter.systemImage)
            .tag("filter:\(filter.displayName)")
    }

    // MARK: - Selection binding helpers

    private var selectionID: String? {
        switch windowVM.selectedFilter {
        case .all:         return "filter:All Notes"
        case .starred:     return "filter:Starred"
        case .pinned:      return "filter:Pinned"
        case .space(let s): return "space:\(s.id.uuidString)"
        case .tag(let t):  return "tag:\(t)"
        }
    }

    private func applySelection(_ id: String?) {
        guard let id else { return }
        if id == "filter:All Notes"  { windowVM.apply(filter: .all);     return }
        if id == "filter:Starred"    { windowVM.apply(filter: .starred); return }
        if id == "filter:Pinned"     { windowVM.apply(filter: .pinned);  return }
        if id.hasPrefix("space:"),
           let uuid = UUID(uuidString: String(id.dropFirst("space:".count))),
           let space = spaces.first(where: { $0.id == uuid })
        { windowVM.apply(filter: .space(space)); return }
        if id.hasPrefix("tag:") {
            let tag = String(id.dropFirst("tag:".count))
            windowVM.apply(filter: .tag(tag))
        }
    }

    // MARK: - New Space sheet

    private var newSpaceSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Space")
                .font(.headline)
            TextField("Space name…", text: $newSpaceName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { createSpace() }
            HStack {
                Spacer()
                Button("Cancel") { isAddingSpace = false }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Create") { createSpace() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .disabled(newSpaceName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Actions

    private func reload() {
        spaces = storageService.fetchSpaces()
        tags   = storageService.fetchAllTags()
    }

    private func createSpace() {
        let name = newSpaceName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let space = Space(name: name, sortOrder: spaces.count)
        _ = storageService.saveSpace(space)
        newSpaceName  = ""
        isAddingSpace = false
        reload()
    }
}
#endif
