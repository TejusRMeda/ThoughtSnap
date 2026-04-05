#if os(macOS)
import Foundation

// MARK: - SearchResult

struct SearchResult: Identifiable {
    let id = UUID()
    let noteID: UUID
    let snippet: String   // HTML with <b>…</b> highlight markers
    let score: Double
}

// MARK: - SearchService
// Full implementation in Week 4.

final class SearchService: ObservableObject {

    private let storageService: StorageService
    private let searchQueue = DispatchQueue(label: "com.thoughtsnap.search", qos: .userInitiated)

    init(storageService: StorageService) {
        self.storageService = storageService
    }

    /// Performs a full-text FTS5 search and returns ranked results.
    /// Runs on a background queue; call from a SwiftUI .task modifier.
    func search(query: String) async -> [SearchResult] {
        await withCheckedContinuation { continuation in
            searchQueue.async { [weak self] in
                guard let self else { continuation.resume(returning: []); return }
                let t0 = CACurrentMediaTime()
                let raw = self.storageService.searchNotes(query: query)
                let elapsed = (CACurrentMediaTime() - t0) * 1000
                if elapsed > 200 {
                    print("[SearchService] ⚠️ SLA VIOLATION: search took \(Int(elapsed))ms (budget: 200ms)")
                }
                let results = raw.enumerated().map { idx, pair in
                    SearchResult(noteID: pair.noteID, snippet: pair.snippet, score: Double(raw.count - idx))
                }
                continuation.resume(returning: results)
            }
        }
    }
}
#endif
