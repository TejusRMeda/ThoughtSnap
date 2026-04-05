#if os(macOS)
import Foundation
import AppKit
import Markdown

// MARK: - MarkdownParser

/// Parses GitHub-flavoured Markdown (via apple/swift-markdown) and renders it
/// to an NSAttributedString for display in NoteDetailView and MarkdownEditor.
///
/// Supported node types:
///   Headings (h1–h6), Strong, Emphasis, InlineCode, CodeBlock,
///   Link, Paragraph, BlockQuote, UnorderedList, OrderedList, ListItem,
///   ThematicBreak, SoftBreak, LineBreak
///
/// ThoughtSnap extensions handled separately (not by swift-markdown):
///   #tag  →  accent-colour foreground
///   [[wiki link]] → underline + accent colour
enum MarkdownParser {

    // MARK: - Theme

    struct Theme {
        var baseFont: NSFont
        var monoFont: NSFont
        var headingScale: [Int: CGFloat]   // h1…h6 point sizes
        var tagColor: NSColor
        var wikiLinkColor: NSColor
        var codeBackground: NSColor

        static func `default`(baseSize: CGFloat = 14) -> Theme {
            Theme(
                baseFont: .systemFont(ofSize: baseSize),
                monoFont: .monospacedSystemFont(ofSize: baseSize - 1, weight: .regular),
                headingScale: [1: 22, 2: 19, 3: 17, 4: 15, 5: 14, 6: 13],
                tagColor: NSColor.systemBlue,
                wikiLinkColor: NSColor.controlAccentColor,
                codeBackground: NSColor.secondarySystemFill
            )
        }
    }

    // MARK: - Entry point

    /// Parses `markdown` and returns a fully attributed string ready for display.
    static func render(_ markdown: String, theme: Theme = .default()) -> NSAttributedString {
        let document = Document(parsing: markdown)
        let result = NSMutableAttributedString()
        visit(document, into: result, theme: theme, context: .init(theme: theme))
        applyThoughtSnapExtensions(to: result, theme: theme)
        return result
    }

    /// Returns only the syntax-highlight ranges without building a full attributed string.
    /// Used by MarkdownEditor for lightweight live highlighting.
    static func highlightRanges(in text: String, theme: Theme = .default()) -> [HighlightRange] {
        var results: [HighlightRange] = []
        let ns = text as NSString

        // #tags — must be preceded by whitespace or start-of-line
        if let re = try? NSRegularExpression(pattern: #"(?:^|\s)(#[\w-]+)"#, options: .anchorsMatchLines) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if m.numberOfRanges > 1 {
                    results.append(HighlightRange(range: m.range(at: 1), kind: .tag,
                                                  color: theme.tagColor))
                }
            }
        }

        // [[wiki links]]
        if let re = try? NSRegularExpression(pattern: #"\[\[.+?\]\]"#) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                results.append(HighlightRange(range: m.range, kind: .wikiLink,
                                              color: theme.wikiLinkColor))
            }
        }

        // **bold** and __bold__
        if let re = try? NSRegularExpression(pattern: #"(\*\*|__)(.+?)(\1)"#) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                results.append(HighlightRange(range: m.range, kind: .bold, color: nil))
            }
        }

        // *italic* and _italic_
        if let re = try? NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                results.append(HighlightRange(range: m.range, kind: .italic, color: nil))
            }
        }

        // `inline code`
        if let re = try? NSRegularExpression(pattern: #"`[^`]+`"#) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                results.append(HighlightRange(range: m.range, kind: .code, color: nil))
            }
        }

        // # Headings (start of line)
        if let re = try? NSRegularExpression(pattern: #"^(#{1,6})\s.+"#, options: .anchorsMatchLines) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                results.append(HighlightRange(range: m.range, kind: .heading, color: nil))
            }
        }

        return results
    }

    // MARK: - HighlightRange

    struct HighlightRange {
        let range: NSRange
        let kind: Kind
        let color: NSColor?
        enum Kind { case tag, wikiLink, bold, italic, code, heading }
    }

    // MARK: - Visitor context

    private struct Context {
        let theme: Theme
        var isBold:      Bool = false
        var isItalic:    Bool = false
        var isCode:      Bool = false
        var headingLevel: Int = 0
        var listDepth:   Int = 0
        var orderedIndex: Int = 1

        var font: NSFont {
            if isCode { return theme.monoFont }
            let size: CGFloat
            if headingLevel > 0 {
                size = theme.headingScale[headingLevel] ?? theme.baseFont.pointSize
            } else {
                size = theme.baseFont.pointSize
            }
            var traits: NSFontTraitMask = []
            if isBold   { traits.insert(.boldFontMask) }
            if isItalic { traits.insert(.italicFontMask) }
            if traits.isEmpty {
                return NSFont.systemFont(ofSize: size)
            }
            return NSFontManager.shared.font(
                withFamily: theme.baseFont.familyName ?? "System",
                traits: traits,
                weight: headingLevel > 0 ? 9 : 5,
                size: size
            ) ?? NSFont.systemFont(ofSize: size)
        }

        var foregroundColor: NSColor {
            headingLevel > 0 ? NSColor.labelColor : NSColor.labelColor
        }
    }

    // MARK: - Node visitor

    private static func visit(_ markup: any Markup, into result: NSMutableAttributedString, theme: Theme, context: Context) {
        switch markup {
        case let heading as Heading:
            var ctx = context
            ctx.headingLevel = heading.level
            ctx.isBold = true
            visitChildren(heading, into: result, theme: theme, context: ctx)
            result.append(NSAttributedString(string: "\n"))

        case let strong as Strong:
            var ctx = context
            ctx.isBold = true
            visitChildren(strong, into: result, theme: theme, context: ctx)

        case let em as Emphasis:
            var ctx = context
            ctx.isItalic = true
            visitChildren(em, into: result, theme: theme, context: ctx)

        case let code as InlineCode:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: theme.monoFont,
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: theme.codeBackground,
            ]
            result.append(NSAttributedString(string: code.code, attributes: attrs))

        case let block as CodeBlock:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: theme.monoFont,
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: theme.codeBackground,
            ]
            result.append(NSAttributedString(string: "\n"))
            result.append(NSAttributedString(string: block.code, attributes: attrs))
            result.append(NSAttributedString(string: "\n"))

        case let link as Markdown.Link:
            var ctx = context
            let urlStr = link.destination ?? ""
            let linkAttrs: [NSAttributedString.Key: Any] = [
                .font: ctx.font,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: urlStr,
            ]
            let inner = NSMutableAttributedString()
            visitChildren(link, into: inner, theme: theme, context: ctx)
            inner.addAttributes(linkAttrs, range: NSRange(location: 0, length: inner.length))
            result.append(inner)

        case let para as Paragraph:
            visitChildren(para, into: result, theme: theme, context: context)
            result.append(NSAttributedString(string: "\n\n"))

        case let quote as BlockQuote:
            var ctx = context
            let quoteAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let inner = NSMutableAttributedString()
            visitChildren(quote, into: inner, theme: theme, context: ctx)
            inner.addAttributes(quoteAttrs, range: NSRange(location: 0, length: inner.length))
            result.append(inner)

        case let list as UnorderedList:
            var ctx = context
            ctx.listDepth += 1
            for item in list.listItems {
                let indent = String(repeating: "    ", count: ctx.listDepth - 1)
                result.append(NSAttributedString(
                    string: "\(indent)• ",
                    attributes: [.font: context.font, .foregroundColor: NSColor.labelColor]
                ))
                visitChildren(item, into: result, theme: theme, context: ctx)
            }

        case let list as OrderedList:
            var ctx = context
            ctx.listDepth += 1
            for (idx, item) in list.listItems.enumerated() {
                let indent = String(repeating: "    ", count: ctx.listDepth - 1)
                result.append(NSAttributedString(
                    string: "\(indent)\(idx + 1). ",
                    attributes: [.font: context.font, .foregroundColor: NSColor.labelColor]
                ))
                visitChildren(item, into: result, theme: theme, context: ctx)
            }

        case let text as Markdown.Text:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: context.font,
                .foregroundColor: context.foregroundColor,
            ]
            result.append(NSAttributedString(string: text.string, attributes: attrs))

        case is SoftBreak:
            result.append(NSAttributedString(string: " "))

        case is LineBreak:
            result.append(NSAttributedString(string: "\n"))

        case is ThematicBreak:
            result.append(NSAttributedString(string: "\n────────────────────────\n",
                attributes: [.foregroundColor: NSColor.separatorColor,
                             .font: NSFont.systemFont(ofSize: 11)]))

        default:
            visitChildren(markup, into: result, theme: theme, context: context)
        }
    }

    private static func visitChildren(_ markup: any Markup, into result: NSMutableAttributedString, theme: Theme, context: Context) {
        for child in markup.children {
            visit(child, into: result, theme: theme, context: context)
        }
    }

    // MARK: - ThoughtSnap extensions (applied as a post-pass)

    private static func applyThoughtSnapExtensions(to str: NSMutableAttributedString, theme: Theme) {
        let text = str.string as NSString
        let full = NSRange(location: 0, length: str.length)

        // #tags
        if let re = try? NSRegularExpression(pattern: #"(?:^|\s)(#[\w-]+)"#, options: .anchorsMatchLines) {
            for m in re.matches(in: str.string, range: full) {
                guard m.numberOfRanges > 1 else { continue }
                str.addAttribute(.foregroundColor, value: theme.tagColor, range: m.range(at: 1))
            }
        }

        // [[wiki links]]
        if let re = try? NSRegularExpression(pattern: #"\[\[.+?\]\]"#) {
            for m in re.matches(in: str.string, range: full) {
                str.addAttributes([
                    .foregroundColor: theme.wikiLinkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: m.range)
            }
        }
    }
}
#endif
