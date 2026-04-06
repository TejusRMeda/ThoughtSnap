#if os(macOS)
import Foundation

// MARK: - SearchResult

struct SearchResult: Identifiable {
    let id = UUID()
    let noteID: UUID
    /// Raw snippet from FTS5 with <b>…</b> markers around matching terms.
    let rawSnippet: String
    let score: Double
}

// MARK: - SearchService

/// Performs full-text searches via SQLite FTS5.
///
/// - Runs on a dedicated serial DispatchQueue (never blocks the main thread)
/// - Uses BM25 ranking
/// - Supports optional tag filter (additive AND)
/// - SLA: <200ms for 10,000 notes
final class SearchService: ObservableObject {

    private let storageService: StorageService
    private let searchQueue = DispatchQueue(
        label: "com.thoughtsnap.search", qos: .userInitiated)

    init(storageService: StorageService) {
        self.storageService = storageService
    }

    // MARK: - Search

    /// Full-text search with optional tag filter.
    /// `tagFilter` — if non-empty, only notes carrying ALL of those tags are returned.
    func search(query: String, tagFilter: [String] = []) async -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return await withCheckedContinuation { continuation in
            searchQueue.async { [weak self] in
                guard let self else { continuation.resume(returning: []); return }

                let t0  = CACurrentMediaTime()
                let raw = self.storageService.searchNotes(query: query)
                let ms  = (CACurrentMediaTime() - t0) * 1000
                if ms > 200 {
                    print("[SearchService] ⚠️ SLA: search \(Int(ms))ms > 200ms")
                }

                var results = raw.enumerated().map { idx, pair in
                    SearchResult(
                        noteID: pair.noteID,
                        rawSnippet: pair.snippet,
                        score: Double(raw.count - idx)
                    )
                }

                // Apply tag filter
                if !tagFilter.isEmpty {
                    let taggedIDs = self.noteIDsMatching(tags: tagFilter)
                    results = results.filter { taggedIDs.contains($0.noteID) }
                }

                continuation.resume(returning: results)
            }
        }
    }

    // MARK: - Tag filter helper

    private func noteIDsMatching(tags: [String]) -> Set<UUID> {
        // For each tag, fetch note IDs; intersect all sets (AND semantics)
        var result: Set<UUID>? = nil
        for tag in tags {
            let ids = storageService.fetchNoteIDs(forTag: tag)
            if result == nil {
                result = ids
            } else {
                result = result!.intersection(ids)
            }
        }
        return result ?? []
    }
}
#endif
