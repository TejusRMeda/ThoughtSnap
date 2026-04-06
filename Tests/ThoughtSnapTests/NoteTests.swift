import XCTest
@testable import ThoughtSnap

final class NoteTests: XCTestCase {

    // MARK: - Tag extraction

    func testExtractsTags() {
        let body = "Fixed the #questflow login bug — see #auth for context"
        let tags = Note.extractTags(from: body)
        XCTAssertEqual(Set(tags), Set(["questflow", "auth"]))
    }

    func testIgnoresMarkdownHeadings() {
        // A `#` at the start of a line with no preceding space is a heading, not a tag
        let body = "# My Heading\nSome text with a #realtag"
        let tags = Note.extractTags(from: body)
        XCTAssertEqual(tags, ["realtag"])
    }

    func testExtractsHyphenatedTags() {
        let body = "Working on #user-onboarding flow"
        let tags = Note.extractTags(from: body)
        XCTAssertEqual(tags, ["user-onboarding"])
    }

    func testTagsAreLowercased() {
        let body = "Issue with #QuestFlow component"
        let tags = Note.extractTags(from: body)
        XCTAssertEqual(tags, ["questflow"])
    }

    // MARK: - Wiki link extraction

    func testExtractsWikiLinks() {
        let body = "See [[Clinical Notes redesign]] and [[Auth Service]]"
        let links = Note.extractWikiLinks(from: body)
        XCTAssertEqual(links, ["Clinical Notes redesign", "Auth Service"])
    }

    func testExtractsNoLinksWhenNone() {
        let body = "Just plain text here"
        let links = Note.extractWikiLinks(from: body)
        XCTAssertTrue(links.isEmpty)
    }

    func testExtractsLinkWithSpecialChars() {
        let body = "Linked to [[API v2.0 design]]"
        let links = Note.extractWikiLinks(from: body)
        XCTAssertEqual(links, ["API v2.0 design"])
    }

    // MARK: - Computed properties

    func testFirstLineExtraction() {
        let note = Note(body: "\n\nHello World\nSecond line")
        XCTAssertEqual(note.firstLine, "Hello World")
    }

    func testFirstLineUntitled() {
        let note = Note(body: "")
        XCTAssertEqual(note.firstLine, "Untitled")
    }

    func testExcerptSkipsFirstLine() {
        let note = Note(body: "Title\nThis is the excerpt content")
        XCTAssertEqual(note.excerpt, "This is the excerpt content")
    }

    func testExcerptTruncatesAt160() {
        let longText = String(repeating: "a", count: 200)
        let note = Note(body: "Title\n\(longText)")
        XCTAssertEqual(note.excerpt.count, 161) // 160 chars + "…"
        XCTAssertTrue(note.excerpt.hasSuffix("…"))
    }

    // MARK: - Equatability

    func testNotesWithSameIDAndBodyAreEqual() {
        let id = UUID()
        let n1 = Note(id: id, body: "Hello")
        let n2 = Note(id: id, body: "Hello")
        XCTAssertEqual(n1, n2)
    }

    func testNotesWithDifferentIDsAreNotEqual() {
        let n1 = Note(id: UUID(), body: "Hello")
        let n2 = Note(id: UUID(), body: "Hello")
        XCTAssertNotEqual(n1, n2)
    }
}
