#if os(macOS)
import XCTest
import Combine
@testable import ThoughtSnap

// MARK: - LinkGraphServiceTests
//
// Integration tests for LinkGraphService — verifies link resolution, stub
// creation, backlink map computation, and edge replacement.

final class LinkGraphServiceTests: XCTestCase {

    private var tempDir: URL!
    private var storage: StorageService!
    private var linkService: LinkGraphService!
    private var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage     = StorageService(directory: tempDir)
        linkService = LinkGraphService(storageService: storage)
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
        linkService = nil
        storage     = nil
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func save(_ body: String, tags: [String] = []) -> Note {
        var note = Note(body: body, spaceIDs: [Space.inbox.id], tags: tags)
        _ = storage.saveNote(note)
        return note
    }

    /// Block until the backlinkMap is published (or timeout after 2s).
    private func waitForBacklinkMap(timeout: TimeInterval = 2.0) {
        let exp = expectation(description: "backlinkMap published")
        exp.assertForOverFulfill = false

        linkService.$backlinkMap
            .dropFirst()          // ignore the initial empty value
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        wait(for: [exp], timeout: timeout)
    }

    // MARK: - resolveLinks (pure helper — no side effects)

    func testResolveLinksFindsByFirstLineExactMatch() {
        let notes = [
            Note(body: "My Design Doc"),
            Note(body: "Another Note"),
        ]
        let ids = linkService.resolveLinks(["My Design Doc"], in: notes)
        XCTAssertEqual(ids, [notes[0].id])
    }

    func testResolveLinksIsCaseInsensitive() {
        let note = Note(body: "Auth Service")
        let ids = linkService.resolveLinks(["auth service"], in: [note])
        XCTAssertEqual(ids, [note.id])
    }

    func testResolveLinksReturnsEmptyForUnknownTitle() {
        let notes = [Note(body: "Existing Note")]
        let ids = linkService.resolveLinks(["No Such Note"], in: notes)
        XCTAssertTrue(ids.isEmpty)
    }

    func testResolveLinksHandlesMultipleTitles() {
        let a = Note(body: "Alpha Note")
        let b = Note(body: "Beta Note")
        let ids = linkService.resolveLinks(["Alpha Note", "Beta Note"], in: [a, b])
        XCTAssertEqual(Set(ids), Set([a.id, b.id]))
    }

    // MARK: - processLinks — edge persistence

    func testProcessLinksCreatesEdgeToExistingNote() {
        let target = save("Target Note")
        let source = save("See [[Target Note]] for details")

        linkService.processLinks(for: source)

        let backlinks = storage.fetchBacklinks(for: target.id)
        XCTAssertTrue(backlinks.contains(source.id),
                      "target should have source as a backlink")
    }

    func testProcessLinksAutoCreatesStubForUnresolvedTitle() {
        let source = save("References [[New Stub Note]]")
        linkService.processLinks(for: source)

        // A stub with firstLine == "New Stub Note" should now exist
        let all = storage.fetchAllNotes(limit: 100, offset: 0)
        XCTAssertTrue(all.contains { $0.firstLine == "New Stub Note" },
                      "Stub note should have been auto-created")
    }

    func testProcessLinksWithNoLinksDoesNotCreateStubs() {
        let before = storage.fetchAllNotes(limit: 100, offset: 0).count
        let note = save("Just plain text, no links here")
        linkService.processLinks(for: note)
        let after = storage.fetchAllNotes(limit: 100, offset: 0).count
        // Only the note itself was added (no stubs)
        XCTAssertEqual(after, before + 1)
    }

    func testProcessLinksReplacesOldEdges() {
        let t1 = save("First Target")
        let t2 = save("Second Target")

        var source = save("See [[First Target]]")
        linkService.processLinks(for: source)
        XCTAssertFalse(storage.fetchBacklinks(for: t1.id).isEmpty)

        // Update source to point to Second Target instead
        source = Note(id: source.id, body: "See [[Second Target]]",
                      updatedAt: Date(), spaceIDs: source.spaceIDs)
        _ = storage.saveNote(source)
        linkService.processLinks(for: source)

        XCTAssertTrue(storage.fetchBacklinks(for: t1.id).isEmpty,
                      "Old link to First Target should be removed")
        XCTAssertTrue(storage.fetchBacklinks(for: t2.id).contains(source.id),
                      "New link to Second Target should exist")
    }

    func testProcessLinksWithEmptyBodyClearsAllLinks() {
        let target = save("Target")
        let source = save("See [[Target]]")
        linkService.processLinks(for: source)
        XCTAssertFalse(storage.fetchBacklinks(for: target.id).isEmpty)

        // Clear body
        let blank = Note(id: source.id, body: "", updatedAt: Date(), spaceIDs: source.spaceIDs)
        _ = storage.saveNote(blank)
        linkService.processLinks(for: blank)

        XCTAssertTrue(storage.fetchBacklinks(for: target.id).isEmpty,
                      "Links should be cleared when body is empty")
    }

    // MARK: - backlinkMap (reactive)

    func testBacklinkMapUpdatedAfterProcessLinks() {
        let target = save("Linked Target")
        let source = save("Mentions [[Linked Target]]")

        let exp = expectation(description: "backlinkMap updated")
        exp.assertForOverFulfill = false

        linkService.$backlinkMap
            .dropFirst()
            .sink { map in
                if map[target.id]?.contains(where: { $0.id == source.id }) == true {
                    exp.fulfill()
                }
            }
            .store(in: &cancellables)

        linkService.processLinks(for: source)
        wait(for: [exp], timeout: 2.0)
    }

    func testBacklinksHelperReturnsCorrectNotes() {
        let target = save("The Target")
        let s1     = save("Link to [[The Target]] one")
        let s2     = save("Link to [[The Target]] two")
        linkService.processLinks(for: s1)
        linkService.processLinks(for: s2)

        waitForBacklinkMap()

        let backlinks = linkService.backlinks(for: target.id)
        XCTAssertEqual(backlinks.count, 2)
        XCTAssertTrue(backlinks.contains { $0.id == s1.id })
        XCTAssertTrue(backlinks.contains { $0.id == s2.id })
    }

    func testBacklinksHelperReturnsEmptyForNoteWithNoIncomingLinks() {
        let orphan = save("No one links here")
        linkService.processLinks(for: orphan)
        waitForBacklinkMap()
        XCTAssertTrue(linkService.backlinks(for: orphan.id).isEmpty)
    }
}
#endif
