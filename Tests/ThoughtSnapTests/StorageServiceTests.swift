#if os(macOS)
import XCTest
@testable import ThoughtSnap

// MARK: - StorageServiceTests
//
// Integration tests that run against a real SQLite database created in a
// per-test temporary directory.  Each test gets a fresh, isolated database.

final class StorageServiceTests: XCTestCase {

    // MARK: Helpers

    private var tempDir: URL!
    private var storage: StorageService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = StorageService(directory: tempDir)
    }

    override func tearDownWithError() throws {
        storage = nil
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private func makeNote(body: String = "Test note",
                          isPinned: Bool = false,
                          isStarred: Bool = false,
                          tags: [String] = [],
                          spaceIDs: [UUID] = [Space.inbox.id]) -> Note {
        Note(
            body: body,
            isPinned: isPinned,
            isStarred: isStarred,
            spaceIDs: spaceIDs,
            tags: tags
        )
    }

    // MARK: - Save & fetch round-trip

    func testSaveAndFetchNote() {
        let note = makeNote(body: "Hello, ThoughtSnap!")
        let result = storage.saveNote(note)
        XCTAssertNoThrow(try result.get())

        let fetched = storage.fetchNote(id: note.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.body, "Hello, ThoughtSnap!")
        XCTAssertEqual(fetched?.id, note.id)
    }

    func testFetchNonExistentNoteReturnsNil() {
        XCTAssertNil(storage.fetchNote(id: UUID()))
    }

    func testSaveNotePreservesAllFields() {
        var note = makeNote(body: "Starred pinned note")
        note = Note(
            id: note.id,
            body: note.body,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            isPinned: true,
            isStarred: true,
            spaceIDs: note.spaceIDs,
            tags: ["swift", "testing"]
        )
        _ = storage.saveNote(note)
        let fetched = storage.fetchNote(id: note.id)
        XCTAssertEqual(fetched?.isPinned, true)
        XCTAssertEqual(fetched?.isStarred, true)
        XCTAssertEqual(Set(fetched?.tags ?? []), Set(["swift", "testing"]))
    }

    // MARK: - Update

    func testUpdateNoteChangesBody() {
        var note = makeNote(body: "Original body")
        _ = storage.saveNote(note)

        note = Note(
            id: note.id,
            body: "Updated body",
            createdAt: note.createdAt,
            updatedAt: Date(),
            spaceIDs: note.spaceIDs
        )
        let updateResult = storage.saveNote(note)
        XCTAssertNoThrow(try updateResult.get())

        let fetched = storage.fetchNote(id: note.id)
        XCTAssertEqual(fetched?.body, "Updated body")
    }

    func testUpdateNoteReplacesTagsCleanly() {
        var note = makeNote(body: "Note", tags: ["old"])
        _ = storage.saveNote(note)

        note = Note(id: note.id, body: "Note", updatedAt: Date(), tags: ["new1", "new2"])
        _ = storage.saveNote(note)

        let fetched = storage.fetchNote(id: note.id)
        XCTAssertEqual(Set(fetched?.tags ?? []), Set(["new1", "new2"]))
    }

    // MARK: - Delete

    func testDeleteNoteRemovesIt() {
        let note = makeNote()
        _ = storage.saveNote(note)
        XCTAssertNotNil(storage.fetchNote(id: note.id))

        let deleteResult = storage.deleteNote(id: note.id)
        XCTAssertNoThrow(try deleteResult.get())
        XCTAssertNil(storage.fetchNote(id: note.id))
    }

    func testDeleteNoteAlsoCascadesToTags() {
        let note = makeNote(body: "Tagged", tags: ["cleanup"])
        _ = storage.saveNote(note)

        _ = storage.deleteNote(id: note.id)

        // Tag should no longer appear in fetchAllTags
        XCTAssertFalse(storage.fetchAllTags().contains("cleanup"))
    }

    // MARK: - Fetch all

    func testFetchAllNotesReturnsAll() {
        (1...5).forEach { i in _ = storage.saveNote(makeNote(body: "Note \(i)")) }
        let notes = storage.fetchAllNotes(limit: 100, offset: 0)
        XCTAssertEqual(notes.count, 5)
    }

    func testFetchAllNotesRespectsPagination() {
        (1...10).forEach { i in _ = storage.saveNote(makeNote(body: "Note \(i)")) }
        let page1 = storage.fetchAllNotes(limit: 4, offset: 0)
        let page2 = storage.fetchAllNotes(limit: 4, offset: 4)
        XCTAssertEqual(page1.count, 4)
        XCTAssertEqual(page2.count, 4)
        // IDs should be disjoint
        let ids1 = Set(page1.map(\.id))
        let ids2 = Set(page2.map(\.id))
        XCTAssertTrue(ids1.isDisjoint(with: ids2))
    }

    // MARK: - Pinned / starred

    func testFetchPinnedNotes() {
        _ = storage.saveNote(makeNote(body: "Regular"))
        let pinned = makeNote(body: "Pinned", isPinned: true)
        _ = storage.saveNote(pinned)

        let results = storage.fetchPinnedNotes()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, pinned.id)
    }

    func testFetchStarredNotes() {
        _ = storage.saveNote(makeNote(body: "Regular"))
        let starred = makeNote(body: "Starred", isStarred: true)
        _ = storage.saveNote(starred)

        let results = storage.fetchStarredNotes()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, starred.id)
    }

    // MARK: - Tags

    func testFetchAllTagsReturnsDistinctSorted() {
        _ = storage.saveNote(makeNote(body: "a", tags: ["beta", "alpha"]))
        _ = storage.saveNote(makeNote(body: "b", tags: ["alpha", "gamma"]))

        let tags = storage.fetchAllTags()
        XCTAssertEqual(tags, ["alpha", "beta", "gamma"])
    }

    func testFetchNotesByTag() {
        let matchNote = makeNote(body: "swift note", tags: ["swift"])
        let otherNote = makeNote(body: "python note", tags: ["python"])
        _ = storage.saveNote(matchNote)
        _ = storage.saveNote(otherNote)

        let results = storage.fetchNotes(withTag: "swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, matchNote.id)
    }

    func testFetchNoteIDsForTag() {
        let n1 = makeNote(body: "a", tags: ["shared", "only-a"])
        let n2 = makeNote(body: "b", tags: ["shared", "only-b"])
        _ = storage.saveNote(n1)
        _ = storage.saveNote(n2)

        let ids = storage.fetchNoteIDs(forTag: "shared")
        XCTAssertEqual(ids, Set([n1.id, n2.id]))

        let idsA = storage.fetchNoteIDs(forTag: "only-a")
        XCTAssertEqual(idsA, Set([n1.id]))
    }

    // MARK: - Spaces

    func testFetchNotesBySpace() {
        let inboxNote = makeNote(body: "Inbox note", spaceIDs: [Space.inbox.id])
        let archiveNote = makeNote(body: "Archive note", spaceIDs: [Space.archive.id])
        _ = storage.saveNote(inboxNote)
        _ = storage.saveNote(archiveNote)

        let inboxNotes = storage.fetchNotes(inSpace: Space.inbox.id)
        XCTAssertTrue(inboxNotes.contains { $0.id == inboxNote.id })
        XCTAssertFalse(inboxNotes.contains { $0.id == archiveNote.id })
    }

    // MARK: - Links

    func testSaveAndFetchLinks() {
        let source = makeNote(body: "Source note")
        let target = makeNote(body: "Target note")
        _ = storage.saveNote(source)
        _ = storage.saveNote(target)

        let linkResult = storage.saveLinks(sourceID: source.id, targetIDs: [target.id])
        XCTAssertNoThrow(try linkResult.get())

        let backlinks = storage.fetchBacklinks(for: target.id)
        XCTAssertEqual(backlinks, [source.id])
    }

    func testSaveLinksReplacesOldEdges() {
        let source  = makeNote(body: "Source")
        let target1 = makeNote(body: "Target 1")
        let target2 = makeNote(body: "Target 2")
        _ = storage.saveNote(source)
        _ = storage.saveNote(target1)
        _ = storage.saveNote(target2)

        _ = storage.saveLinks(sourceID: source.id, targetIDs: [target1.id])
        _ = storage.saveLinks(sourceID: source.id, targetIDs: [target2.id])

        // target1 should no longer have a backlink from source
        XCTAssertTrue(storage.fetchBacklinks(for: target1.id).isEmpty)
        XCTAssertEqual(storage.fetchBacklinks(for: target2.id), [source.id])
    }

    func testSaveLinksWithEmptyArrayClearsLinks() {
        let source = makeNote(body: "Source")
        let target = makeNote(body: "Target")
        _ = storage.saveNote(source)
        _ = storage.saveNote(target)
        _ = storage.saveLinks(sourceID: source.id, targetIDs: [target.id])

        _ = storage.saveLinks(sourceID: source.id, targetIDs: [])
        XCTAssertTrue(storage.fetchBacklinks(for: target.id).isEmpty)
    }

    // MARK: - FTS search

    func testSearchFindsNoteByBodyWord() {
        let note = makeNote(body: "Refactoring the authentication module")
        _ = storage.saveNote(note)

        let results = storage.searchNotes(query: "authentication")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.noteID == note.id })
    }

    func testSearchReturnsEmptyForBlankQuery() {
        _ = storage.saveNote(makeNote(body: "Some content"))
        XCTAssertTrue(storage.searchNotes(query: "   ").isEmpty)
    }

    func testSearchDoesNotReturnUnrelatedNote() {
        _ = storage.saveNote(makeNote(body: "Completely unrelated text"))
        let results = storage.searchNotes(query: "authentication")
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchResultSnippetContainsBoldMarkers() {
        let note = makeNote(body: "The quick brown fox jumps over the lazy dog")
        _ = storage.saveNote(note)

        let results = storage.searchNotes(query: "quick")
        XCTAssertFalse(results.isEmpty)
        let snippet = results.first?.snippet ?? ""
        XCTAssertTrue(snippet.contains("<b>") || snippet.contains("quick"),
                      "Snippet should contain the matched term or bold markers")
    }

    // MARK: - Attachments

    func testSaveAndFetchAttachment() {
        let note = makeNote()
        _ = storage.saveNote(note)

        let attachment = Attachment(
            type: .screenshot,
            filePath: "attachments/test.png"
        )
        let result = storage.saveAttachment(attachment, for: note.id)
        XCTAssertNoThrow(try result.get())

        let fetched = storage.fetchNote(id: note.id)
        XCTAssertEqual(fetched?.attachments.count, 1)
        XCTAssertEqual(fetched?.attachments.first?.filePath, "attachments/test.png")
    }
}
#endif
