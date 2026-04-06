#if os(macOS)
import XCTest
import AppKit
@testable import ThoughtSnap

// MARK: - MarkdownParserTests
//
// Tests for MarkdownParser.render(_:theme:) and MarkdownParser.highlightRanges(in:theme:).
// We test via the returned NSAttributedString attributes and highlight-range metadata
// rather than pixel-level rendering.

final class MarkdownParserTests: XCTestCase {

    private let theme = MarkdownParser.Theme.default(baseSize: 14)

    // MARK: - Helpers

    /// Collects every attribute value of type `T` found at any character position.
    private func attributeValues<T>(
        _ key: NSAttributedString.Key,
        in attrStr: NSAttributedString
    ) -> [T] {
        var found: [T] = []
        attrStr.enumerateAttribute(key, in: NSRange(location: 0, length: attrStr.length)) { val, _, _ in
            if let v = val as? T { found.append(v) }
        }
        return found
    }

    // MARK: - render: plain text

    func testRenderPlainTextPreservesContent() {
        let result = MarkdownParser.render("Hello, world!", theme: theme)
        XCTAssertTrue(result.string.contains("Hello, world!"))
    }

    func testRenderEmptyStringDoesNotCrash() {
        let result = MarkdownParser.render("", theme: theme)
        XCTAssertEqual(result.string.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    // MARK: - render: headings

    func testH1HasLargerFontThanBodyText() {
        let result = MarkdownParser.render("# Big Heading\nBody text", theme: theme)
        let fonts: [NSFont] = attributeValues(.font, in: result)
        let maxSize = fonts.map(\.pointSize).max() ?? 0
        XCTAssertGreaterThan(maxSize, 14, "H1 should be larger than base 14pt body text")
    }

    func testH1HasBoldFont() {
        let result = MarkdownParser.render("# Heading One", theme: theme)
        let fonts: [NSFont] = attributeValues(.font, in: result)
        let hasBold = fonts.contains { $0.fontDescriptor.symbolicTraits.contains(.bold) }
        XCTAssertTrue(hasBold, "H1 should use a bold font")
    }

    // MARK: - render: bold / emphasis

    func testBoldTextHasBoldFontTrait() {
        let result = MarkdownParser.render("This is **important** text.", theme: theme)
        let fonts: [NSFont] = attributeValues(.font, in: result)
        let hasBold = fonts.contains { $0.fontDescriptor.symbolicTraits.contains(.bold) }
        XCTAssertTrue(hasBold, "**bold** should produce a bold font trait")
    }

    func testItalicTextHasItalicFontTrait() {
        let result = MarkdownParser.render("This is *emphasized* text.", theme: theme)
        let fonts: [NSFont] = attributeValues(.font, in: result)
        let hasItalic = fonts.contains { $0.fontDescriptor.symbolicTraits.contains(.italic) }
        XCTAssertTrue(hasItalic, "*italic* should produce an italic font trait")
    }

    // MARK: - render: inline code

    func testInlineCodeUsesMonospacedFont() {
        let result = MarkdownParser.render("Call `print()` to log.", theme: theme)
        let fonts: [NSFont] = attributeValues(.font, in: result)
        let hasMono = fonts.contains { NSFontManager.shared.traits(of: $0).contains(.fixedPitchFontMask) }
        XCTAssertTrue(hasMono, "`code` should use a monospaced font")
    }

    // MARK: - render: ThoughtSnap extensions

    func testHashtagsGetBlueColor() {
        let result = MarkdownParser.render("Working on #swift today", theme: theme)
        let colors: [NSColor] = attributeValues(.foregroundColor, in: result)
        // The tag colour is systemBlue; check that some character has a blue-ish foreground
        let hasBlue = colors.contains { color in
            guard let c = color.usingColorSpace(.sRGB) else { return false }
            return c.blueComponent > 0.5 && c.redComponent < 0.5
        }
        XCTAssertTrue(hasBlue, "#tag should be colored blue")
    }

    func testWikiLinksGetAccentColor() {
        let result = MarkdownParser.render("See [[Design Doc]] for details", theme: theme)
        // Check for underline style — wiki links are rendered with underline
        let underlines: [Int] = attributeValues(.underlineStyle, in: result)
        XCTAssertFalse(underlines.isEmpty, "[[wiki link]] should have an underline attribute")
    }

    // MARK: - highlightRanges: #tags

    func testHighlightRangesDetectsHashtag() {
        let ranges = MarkdownParser.highlightRanges(in: "Fix the #bug today", theme: theme)
        let tagRanges = ranges.filter { $0.kind == .tag }
        XCTAssertEqual(tagRanges.count, 1)
    }

    func testHighlightRangesDetectsMultipleHashtags() {
        let text = "Tagged as #swift and #ios"
        let ranges = MarkdownParser.highlightRanges(in: text, theme: theme)
        let tagRanges = ranges.filter { $0.kind == .tag }
        XCTAssertEqual(tagRanges.count, 2)
    }

    func testHighlightRangesIgnoresMarkdownHeadings() {
        // A leading `#` is a heading, not a tag
        let ranges = MarkdownParser.highlightRanges(in: "# My Heading", theme: theme)
        let tagRanges = ranges.filter { $0.kind == .tag }
        XCTAssertTrue(tagRanges.isEmpty, "# heading should not be treated as a #tag")
    }

    func testHighlightRangesTagColorIsBlue() {
        let ranges = MarkdownParser.highlightRanges(in: "A #tag here", theme: theme)
        let tagRange = ranges.first { $0.kind == .tag }
        XCTAssertNotNil(tagRange)
        XCTAssertEqual(tagRange?.color, NSColor.systemBlue)
    }

    // MARK: - highlightRanges: [[wiki links]]

    func testHighlightRangesDetectsWikiLink() {
        let ranges = MarkdownParser.highlightRanges(in: "See [[Target Note]]", theme: theme)
        let wikiRanges = ranges.filter { $0.kind == .wikiLink }
        XCTAssertEqual(wikiRanges.count, 1)
    }

    func testHighlightRangesDetectsMultipleWikiLinks() {
        let text = "[[Note A]] and [[Note B]] discussed"
        let ranges = MarkdownParser.highlightRanges(in: text, theme: theme)
        let wikiRanges = ranges.filter { $0.kind == .wikiLink }
        XCTAssertEqual(wikiRanges.count, 2)
    }

    func testHighlightRangesWikiLinkSpansFullBrackets() {
        let text = "See [[My Design Doc]]"
        let ranges = MarkdownParser.highlightRanges(in: text, theme: theme)
        guard let wikiRange = ranges.first(where: { $0.kind == .wikiLink }) else {
            XCTFail("Expected a wiki link range"); return
        }
        let matched = (text as NSString).substring(with: wikiRange.range)
        XCTAssertEqual(matched, "[[My Design Doc]]")
    }

    // MARK: - highlightRanges: bold / italic / code

    func testHighlightRangesDetectsBold() {
        let ranges = MarkdownParser.highlightRanges(in: "This is **bold** text", theme: theme)
        XCTAssertTrue(ranges.contains { $0.kind == .bold })
    }

    func testHighlightRangesDetectsItalic() {
        let ranges = MarkdownParser.highlightRanges(in: "This is *italic* text", theme: theme)
        XCTAssertTrue(ranges.contains { $0.kind == .italic })
    }

    func testHighlightRangesDetectsInlineCode() {
        let ranges = MarkdownParser.highlightRanges(in: "Call `func()` here", theme: theme)
        XCTAssertTrue(ranges.contains { $0.kind == .code })
    }

    func testHighlightRangesDetectsHeading() {
        let ranges = MarkdownParser.highlightRanges(in: "# Section Title", theme: theme)
        XCTAssertTrue(ranges.contains { $0.kind == .heading })
    }

    // MARK: - highlightRanges: no false positives

    func testHighlightRangesNoResultsForPlainText() {
        let ranges = MarkdownParser.highlightRanges(in: "Just plain text with nothing special")
        XCTAssertTrue(ranges.isEmpty)
    }
}
#endif
