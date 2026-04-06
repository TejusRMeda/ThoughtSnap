#if os(macOS)
import SwiftUI
import AppKit

// MARK: - TimelineView

/// The centre column of the main window: a paginated, date-grouped list of notes.
///
/// Layout:
///   ─ Pinned section (if any pinned notes exist)
///   ─ Date sections: Today / Yesterday / This Week / Earlier
///
/// Pagination: 50 notes per page; when the last visible row appears, the next
/// page is fetched and appended.
struct TimelineView: View {

    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var windowVM:       MainWindowViewModel

    // MARK: State

    @State private var notes:        [Note] = []
    @State private var pinnedNotes:  [Note] = []
    @State private var isLoadingMore = false
    @State private var hasMore       = true
    private let pageSize = 50

    // MARK: Body

    var body: some View {
        Group {
            if windowVM.isSearching {
                SearchResultsView(query: windowVM.searchQuery) { note in
                    windowVM.select(note: note)
                }
                .environmentObject(storageService)
            } else {
                noteList
            }
        }
        .navigationTitle(windowVM.selectedFilter.displayName)
        .toolbar { toolbarContent }
        .onAppear { reload() }
        .onChange(of: windowVM.selectedFilter) { _ in reload() }
    }

    // MARK: - Note list

    private var noteList: some View {
        List(selection: Binding(
            get:  { windowVM.selectedNoteID },
            set:  { windowVM.selectedNoteID = $0 }
        )) {
            // Pinned section
            if !pinnedNotes.isEmpty {
                Section {
                    ForEach(pinnedNotes) { note in
                        NoteRowView(note: note)
                            .tag(note.id)
                            .swipeActions(edge: .leading)  { starAction(note) }
                            .swipeActions(edge: .trailing) { deleteAction(note); pinAction(note) }
                    }
                } header: {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // Date-grouped sections
            ForEach(dateSections, id: \.title) { section in
                Section {
                    ForEach(section.notes) { note in
                        NoteRowView(note: note)
                            .tag(note.id)
                            .swipeActions(edge: .leading)  { starAction(note) }
                            .swipeActions(edge: .trailing) { deleteAction(note); pinAction(note) }
                    }
                } header: {
                    Text(section.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // Pagination trigger
            if hasMore && !notes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .onAppear { loadNextPage() }
            }
        }
        .listStyle(.inset)
        .animation(.easeInOut(duration: 0.2), value: notes.count)
    }

    // MARK: - Date sections

    private var dateSections: [DateSection] {
        let calendar = Calendar.current
        let now = Date()

        let grouped = Dictionary(grouping: notes) { note -> DateBucket in
            let days = calendar.dateComponents([.day], from: note.updatedAt, to: now).day ?? 0
            if calendar.isDateInToday(note.updatedAt)     { return .today }
            if calendar.isDateInYesterday(note.updatedAt) { return .yesterday }
            if days <= 7                                   { return .thisWeek }
            return .earlier
        }

        return DateBucket.allCases.compactMap { bucket in
            guard let bucketNotes = grouped[bucket], !bucketNotes.isEmpty else { return nil }
            return DateSection(title: bucket.title, notes: bucketNotes)
        }
    }

    // MARK: - Pagination

    private func reload() {
        notes = []; pinnedNotes = []; hasMore = true
        pinnedNotes = storageService.fetchPinnedNotes()
        loadNextPage()
    }

    private func loadNextPage() {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let fetched = storageService.fetchAllNotes(
            limit: pageSize,
            offset: notes.count,
            filtered: windowVM.selectedFilter
        )
        notes.append(contentsOf: fetched)
        hasMore = fetched.count == pageSize
        isLoadingMore = false
    }

    // MARK: - Swipe actions

    private func starAction(_ note: Note) -> some View {
        Button {
            var updated = note
            updated.isStarred.toggle()
            _ = storageService.saveNote(updated)
            reload()
        } label: {
            Label(note.isStarred ? "Unstar" : "Star",
                  systemImage: note.isStarred ? "star.slash" : "star.fill")
        }
        .tint(.yellow)
    }

    private func pinAction(_ note: Note) -> some View {
        Button {
            var updated = note
            updated.isPinned.toggle()
            _ = storageService.saveNote(updated)
            reload()
        } label: {
            Label(note.isPinned ? "Unpin" : "Pin",
                  systemImage: note.isPinned ? "pin.slash" : "pin")
        }
        .tint(.blue)
    }

    private func deleteAction(_ note: Note) -> some View {
        Button(role: .destructive) {
            _ = storageService.deleteNote(id: note.id)
            if windowVM.selectedNoteID == note.id { windowVM.selectedNoteID = nil }
            reload()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: newNote) {
                Image(systemName: "square.and.pencil")
            }
            .help("New note (⌘N)")
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private func newNote() {
        // Trigger the capture panel via notification
        NotificationCenter.default.post(name: .showCapturePanel, object: nil)
    }
}

// MARK: - NoteRowView

struct NoteRowView: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Screenshot thumbnail (if any)
            if let screenshot = note.attachments.first(where: { $0.type == .screenshot }) {
                ScreenshotThumbnail(url: screenshot.absoluteFileURL)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Title row
                HStack {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if note.isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }
                    Text(note.firstLine)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text(note.updatedAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                // Excerpt
                if !note.excerpt.isEmpty {
                    Text(note.excerpt)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Tags
                if !note.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(note.tags.prefix(4), id: \.self) { tag in
                            TagView(tag: tag)
                        }
                        if note.tags.count > 4 {
                            Text("+\(note.tags.count - 4)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - DateBucket

private enum DateBucket: CaseIterable {
    case today, yesterday, thisWeek, earlier

    var title: String {
        switch self {
        case .today:     return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek:  return "This Week"
        case .earlier:   return "Earlier"
        }
    }
}

private struct DateSection {
    let title: String
    let notes: [Note]
}

// MARK: - StorageService filter extension

extension StorageService {
    func fetchAllNotes(limit: Int, offset: Int, filtered: TimelineFilter) -> [Note] {
        switch filtered {
        case .all:
            return fetchAllNotes(limit: limit, offset: offset)
        case .starred:
            return fetchStarredNotes(limit: limit, offset: offset)
        case .pinned:
            return fetchPinnedNotes()
        case .space(let space):
            return fetchNotes(inSpace: space.id, limit: limit, offset: offset)
        case .tag(let tag):
            return fetchNotes(withTag: tag, limit: limit, offset: offset)
        }
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let showCapturePanel = Notification.Name("com.thoughtsnap.showCapturePanel")
}
#endif
