#if os(macOS)
import SwiftUI

// MARK: - SearchResultsView  (stub — full implementation Week 5)

struct SearchResultsView: View {
    let query: String
    @EnvironmentObject var storageService: StorageService
    @State private var results: [SearchResult] = []

    private let searchService: SearchService

    init(query: String, storageService: StorageService) {
        self.query = query
        self.searchService = SearchService(storageService: storageService)
    }

    var body: some View {
        List(results) { result in
            Text(result.snippet)
                .font(.system(size: 13))
        }
        .task(id: query) {
            results = await searchService.search(query: query)
        }
    }
}
#endif
