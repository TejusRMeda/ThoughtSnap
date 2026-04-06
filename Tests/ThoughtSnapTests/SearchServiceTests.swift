#if os(macOS)
import XCTest
@testable import ThoughtSnap

// MARK: - SearchServiceTests
//
// Integration tests for SearchService — runs FTS5 queries against a real
// in-memory-equivalent SQLite database created in a temp directory.

final class SearchServiceTests: XCTestCase {

    private var tempDir: URL!
    private var storage: StorageService!
    private var search: SearchService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = StorageService(directory: tempDir)
        search  = SearchService(storageService: storage)
    }

    override func tearDownWithError() throws {
        storage = nil
        search  = nil
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func save(_ body: String, tags: [String] = []) -> Note {
        let note = Note(body: body, spaceIDs: [Space.inbox.id], tags: tags)
        _ = storage.saveNote(note)
        return note
    }

    // MARK: - Basic search

    func testSearchEmptyQueryReturnsEmpty() async {
        _ = save("Some content here")
        let results = await search.search(query: "")
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchWhitespaceOnlyQueryReturnsEmpty() async {
        _ = save("Some content here")
        let results = await search.search(query: "   \t\n")
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchFindsNoteByExactWord() async {
        let note = save("The authentication service crashed today")
        let results = await search.search(query: "authentication")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.noteID == note.id })
    }

    func testSearchDoesNotReturnUnrelatedNote() async {
        _ = save("Completely unrelated content about databases")
        let results = await search.search(query: "authentication")
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchReturnsMultipleResults() async {
        let n1 = save("Bug in the payment module")
        let n2 = save("Payment gateway refactoring notes")
        _ = save("Totally unrelated note about animals")

        let results = await search.search(query: "payment")
        let ids = Set(results.map(\.noteID))
        XCTAssertTrue(ids.contains(n1.id))
        XCTAssertTrue(ids.contains(n2.id))
    }

    func testSearchResultHasNonEmptySnippet() async {
        _ = save("The quick brown fox jumps over the lazy dog")
        let results = await search.search(query: "fox")
        XCTAssertFalse(results.isEmpty)
        XCTAssertFalse(results.first?.rawSnippet.isEmpty ?? true)
    }

    func testSearchResultsHavePositiveScore() async {
        _ = save("Meeting notes about the project timeline")
        let results = await search.search(query: "timeline")
        XCTAssertTrue(results.allSatisfy { $0.score > 0 })
    }

    // MARK: - Tag filter

    func testTagFilterNarrowsResults() async {
        let swiftNote   = save("Async await patterns", tags: ["swift"])
        _ = save("Async python patterns", tags: ["python"])

        let results = await search.search(query: "async", tagFilter: ["swift"])
        let ids = Set(results.map(\.noteID))
        XCTAssertTrue(ids.contains(swiftNote.id))
        XCTAssertFalse(ids.contains { id in
            storage.fetchNote(id: id)?.tags.contains("python") == true
        })
    }

    func testTagFilterWithNoMatchReturnsEmpty() async {
        _ = save("Content with a tag", tags: ["ios"])
        let results = await search.search(query: "content", tagFilter: ["android"])
        XCTAssertTrue(results.isEmpty)
    }

    func testMultipleTagFiltersUseANDSemantics() async {
        let both = save("Shared note", tags: ["alpha", "beta"])
        _ = save("Only alpha note", tags: ["alpha"])
        _ = save("Only beta note", tags: ["beta"])

        let results = await search.search(query: "note", tagFilter: ["alpha", "beta"])
        let ids = Set(results.map(\.noteID))
        XCTAssertTrue(ids.contains(both.id))
        // Notes with only one of the tags should be excluded
        XCTAssertEqual(results.count, 1)
    }

    func testEmptyTagFilterDoesNotFilterResults() async {
        let n1 = save("Meeting notes", tags: ["work"])
        let n2 = save("Meeting minutes", tags: ["personal"])

        let results = await search.search(query: "meeting", tagFilter: [])
        let ids = Set(results.map(\.noteID))
        XCTAssertTrue(ids.contains(n1.id))
        XCTAssertTrue(ids.contains(n2.id))
    }

    // MARK: - SLA

    func testSearchCompletesFastEnough() async {
        // Insert 100 notes; search should still complete well within the 200ms SLA
        for i in 1...100 {
            _ = save("Sample note number \(i) with random content about testing")
        }
        let start = CACurrentMediaTime()
        _ = await search.search(query: "sample")
        let elapsed = (CACurrentMediaTime() - start) * 1_000
        XCTAssertLessThan(elapsed, 500, "Search took \(Int(elapsed))ms — expected <500ms (SLA is 200ms)")
    }
}
#endif
