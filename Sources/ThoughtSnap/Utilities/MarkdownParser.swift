#if os(macOS)
import Foundation
import AppKit
import Markdown

// MARK: - MarkdownParser
// Week 4 will flesh this out fully (heading sizes, bold, italic, code blocks, etc.)
// For now: plain string extraction and link/tag parsing only.

enum MarkdownParser {

    // MARK: - Rendered attributed string (Week 4 placeholder)

    /// Renders a Markdown string to an NSAttributedString.
    /// Full rendering (headings, bold, italic, code) is implemented in Week 4.
    static func render(_ markdown: String, baseFont: NSFont = .systemFont(ofSize: 14)) -> NSAttributedString {
        NSAttributedString(
            string: markdown,
            attributes: [.font: baseFont, .foregroundColor: NSColor.labelColor]
        )
    }

    // MARK: - Highlight ranges for MarkdownEditor syntax colouring (Week 4)

    struct HighlightRange {
        let range: NSRange
        let kind: Kind
        enum Kind { case tag, wikiLink, bold, italic, code, heading }
    }

    /// Returns ranges that should be syntax-highlighted in the editor.
    static func highlightRanges(in text: String) -> [HighlightRange] {
        var results: [HighlightRange] = []
        let ns = text as NSString

        // #tags
        if let re = try? NSRegularExpression(pattern: #"(?:^|\s)(#[\w-]+)"#, options: .anchorsMatchLines) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if m.numberOfRanges > 1 {
                    results.append(HighlightRange(range: m.range(at: 1), kind: .tag))
                }
            }
        }

        // [[wiki links]]
        if let re = try? NSRegularExpression(pattern: #"\[\[.+?\]\]"#) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                results.append(HighlightRange(range: m.range, kind: .wikiLink))
            }
        }

        return results
    }
}
#endif
