#if os(macOS)
import SwiftUI

// MARK: - SearchResultsView

/// Replaces the TimelineView content when the user types in the search bar.
/// Results come from SearchService (FTS5 + BM25 ranking).
/// Snippets are rendered with <b>…</b> markers converted to bold AttributedString.
struct SearchResultsView: View {

    let query: String
    var tagFilter: [String] = []
    var onSelectNote: ((Note) -> Void)? = nil

    @EnvironmentObject var storageService: StorageService
    @State private var results: [SearchResult] = []
    @State private var resolvedNotes: [UUID: Note] = [:]
    @State private var isSearching = false

    private var searchService: SearchService {
        SearchService(storageService: storageService)
    }

    var body: some View {
        Group {
            if isSearching {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .task(id: query + tagFilter.joined()) {
            await runSearch()
        }
    }

    // MARK: - Results list

    private var resultsList: some View {
        List(results) { result in
            if let note = resolvedNotes[result.noteID] {
                SearchResultRow(note: note, result: result)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelectNote?(note) }
                    .listRowSeparator(.visible)
            }
        }
        .listStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: results.count)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No results for "\(query)"")
                .font(.system(size: 15, weight: .medium))
            Text("Try a different word, or capture a new note.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Search execution

    private func runSearch() async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            resolvedNotes = [:]
            return
        }
        isSearching = true
        let svc = SearchService(storageService: storageService)
        let found = await svc.search(query: query, tagFilter: tagFilter)

        // Resolve note IDs → Note objects
        var noteMap: [UUID: Note] = [:]
        for result in found {
            if let note = storageService.fetchNote(id: result.noteID) {
                noteMap[result.noteID] = note
            }
        }

        results = found
        resolvedNotes = noteMap
        isSearching = false
    }
}

// MARK: - SearchResultRow

struct SearchResultRow: View {
    let note: Note
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Title
            Text(note.firstLine)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            // Snippet with bold matches
            boldSnippet(result.rawSnippet)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            // Tags + date
            HStack(spacing: 6) {
                ForEach(note.tags.prefix(3), id: \.self) { tag in
                    TagView(tag: tag)
                }
                Spacer()
                Text(note.updatedAt, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            // Screenshot thumbnail if present
            if let firstScreenshot = note.attachments.first(where: { $0.type == .screenshot }) {
                ScreenshotThumbnail(url: firstScreenshot.absoluteFileURL)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Bold snippet

    /// Converts an FTS5 snippet string like "some <b>matching</b> text" to
    /// an AttributedString with the matched portions bolded.
    private func boldSnippet(_ raw: String) -> Text {
        // Split on <b> and </b> tags
        var result = Text("")
        var remaining = raw

        while !remaining.isEmpty {
            if let boldStart = remaining.range(of: "<b>"),
               let boldEnd   = remaining.range(of: "</b>") {
                // Text before <b>
                let before = String(remaining[remaining.startIndex..<boldStart.lowerBound])
                if !before.isEmpty { result = result + Text(before) }

                // Bold text between <b> and </b>
                let boldText = String(remaining[boldStart.upperBound..<boldEnd.lowerBound])
                result = result + Text(boldText).bold().foregroundStyle(Color(NSColor.labelColor))

                remaining = String(remaining[boldEnd.upperBound...])
            } else {
                result = result + Text(remaining)
                break
            }
        }
        return result
    }
}
#endif
