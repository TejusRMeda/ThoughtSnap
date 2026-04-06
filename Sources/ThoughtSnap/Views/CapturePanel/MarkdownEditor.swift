#if os(macOS)
import SwiftUI
import AppKit

// MARK: - MarkdownEditor

/// NSTextView-based Markdown editor with:
///   - Live syntax highlighting (bold, italic, code, headings, #tags, [[links]])
///   - `[[` trigger → WikiLinkAutocomplete floating panel
///   - `#` trigger  → TagAutocomplete floating panel
///
/// The highlighting runs in `NSTextStorageDelegate.textStorage(_:didProcessEditing:)`,
/// which fires after every edit without blocking input.
struct MarkdownEditor: NSViewRepresentable {

    @Binding var text: String
    /// All existing notes — provided for [[wiki link]] autocomplete.
    var allNotes: [Note] = []
    /// All existing tags — provided for #tag autocomplete.
    var allTags: [String] = []
    /// Called when the user selects a wiki-link suggestion.
    var onWikiLinkSelected: ((Note) -> Void)? = nil
    /// Called when the user selects a tag suggestion.
    var onTagSelected: ((String) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate            = context.coordinator
        textView.isRichText          = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled  = false
        textView.allowsUndo          = true
        textView.backgroundColor     = .clear
        textView.drawsBackground     = false
        textView.textContainerInset  = NSSize(width: 4, height: 6)
        textView.font                = NSFont.systemFont(ofSize: 14)
        textView.textColor           = NSColor.labelColor
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true

        textView.textStorage?.delegate = context.coordinator

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.allNotes = allNotes
        context.coordinator.allTags  = allTags
        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            // Restore caret (clamped to new length)
            let safeEnd = min(sel.location, textView.string.count)
            textView.setSelectedRange(NSRange(location: safeEnd, length: 0))
            context.coordinator.applyHighlighting(to: textView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {

        var parent: MarkdownEditor
        var allNotes: [Note] = []
        var allTags:  [String] = []

        // Autocomplete state
        private var wikiPanel: AutocompletePanel?
        private var tagPanel:  AutocompletePanel?
        private var suppressHighlight = false

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        // MARK: NSTextStorageDelegate

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard !suppressHighlight,
                  editedMask.contains(.editedCharacters)
            else { return }
            applyHighlighting(to: textStorage)
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            checkAutocomplete(in: tv)
        }

        // MARK: - Syntax highlighting

        func applyHighlighting(to storage: NSTextStorage) {
            let text  = storage.string
            let full  = NSRange(location: 0, length: storage.length)
            let theme = MarkdownParser.Theme.default()

            suppressHighlight = true
            storage.beginEditing()

            // Reset to base appearance
            storage.addAttributes([
                .font: theme.baseFont,
                .foregroundColor: NSColor.labelColor,
            ], range: full)

            for hr in MarkdownParser.highlightRanges(in: text, theme: theme) {
                guard hr.range.location + hr.range.length <= storage.length else { continue }
                switch hr.kind {
                case .tag:
                    storage.addAttribute(.foregroundColor, value: theme.tagColor, range: hr.range)
                case .wikiLink:
                    storage.addAttributes([
                        .foregroundColor: theme.wikiLinkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                    ], range: hr.range)
                case .bold:
                    let size = theme.baseFont.pointSize
                    storage.addAttribute(.font,
                        value: NSFont.boldSystemFont(ofSize: size), range: hr.range)
                case .italic:
                    let size = theme.baseFont.pointSize
                    let italic = NSFontManager.shared.convert(
                        NSFont.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
                    storage.addAttribute(.font, value: italic, range: hr.range)
                case .code:
                    storage.addAttributes([
                        .font: theme.monoFont,
                        .backgroundColor: theme.codeBackground,
                    ], range: hr.range)
                case .heading:
                    // Detect heading level by counting leading #
                    let ns = text as NSString
                    let headText = ns.substring(with: hr.range)
                    let level = headText.prefix(while: { $0 == "#" }).count.clamped(to: 1...6)
                    let size = theme.headingScale[level] ?? theme.baseFont.pointSize
                    storage.addAttribute(.font,
                        value: NSFont.boldSystemFont(ofSize: size), range: hr.range)
                }
            }

            storage.endEditing()
            suppressHighlight = false
        }

        func applyHighlighting(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            applyHighlighting(to: storage)
        }

        // MARK: - Autocomplete detection

        private func checkAutocomplete(in tv: NSTextView) {
            let text    = tv.string
            let nsText  = text as NSString
            let caretIdx = tv.selectedRange().location
            guard caretIdx > 0 else {
                dismissAll()
                return
            }

            // ── [[wiki link]] trigger ──
            // Look for [[ in the text before the caret
            let before = nsText.substring(to: caretIdx)
            if let wikiRange = before.range(of: "[[", options: .backwards),
               !before[wikiRange.upperBound...].contains("]")
            {
                let query = String(before[wikiRange.upperBound...])
                let suggestions = allNotes.filter { note in
                    query.isEmpty || note.firstLine.localizedCaseInsensitiveContains(query)
                }.prefix(8)

                if suggestions.isEmpty {
                    dismissWikiPanel()
                } else {
                    showWikiPanel(
                        suggestions: Array(suggestions),
                        textView: tv,
                        query: query,
                        replaceStart: caretIdx - query.count - 2  // back over [[ + query
                    )
                }
                dismissTagPanel()
                return
            }

            // ── #tag trigger ──
            // Look for # preceded by whitespace or start-of-string
            if let hashRange = before.range(of: "#", options: .backwards) {
                let beforeHash = String(before[before.startIndex..<hashRange.lowerBound])
                let afterHash  = String(before[hashRange.upperBound...])

                // Valid tag trigger: # at start or preceded by whitespace, followed by word chars only
                let isValidTrigger = beforeHash.isEmpty || beforeHash.last?.isWhitespace == true
                let isValidTag     = afterHash.range(of: #"^[\w-]*$"#, options: .regularExpression) != nil

                if isValidTrigger && isValidTag && !afterHash.isEmpty {
                    let suggestions = allTags.filter { $0.hasPrefix(afterHash.lowercased()) }.sorted().prefix(8)
                    if suggestions.isEmpty {
                        dismissTagPanel()
                    } else {
                        showTagPanel(
                            suggestions: Array(suggestions),
                            textView: tv,
                            query: afterHash,
                            replaceStart: caretIdx - afterHash.count - 1 // back over # + query
                        )
                    }
                    dismissWikiPanel()
                    return
                }
            }

            dismissAll()
        }

        // MARK: - Panel management

        private func showWikiPanel(suggestions: [Note], textView: NSTextView, query: String, replaceStart: Int) {
            dismissWikiPanel()
            let caretIdx = textView.selectedRange().location
            guard caretIdx > 0 else { return }
            let rect = textView.firstRect(forCharacterRange: NSRange(location: caretIdx, length: 0), actualRange: nil)

            let panel = AutocompletePanel(anchorScreenRect: rect) {
                AutocompleteList(items: suggestions.map { note in
                    AutocompleteItem(title: note.firstLine, subtitle: nil)
                }) { [weak self, weak textView] idx in
                    guard let tv = textView, idx < suggestions.count else { return }
                    let chosen = suggestions[idx]
                    self?.insertWikiLink(note: chosen, textView: tv, replaceStart: replaceStart)
                    self?.parent.onWikiLinkSelected?(chosen)
                    self?.dismissWikiPanel()
                }
            }
            wikiPanel = panel
            panel.show()
        }

        private func showTagPanel(suggestions: [String], textView: NSTextView, query: String, replaceStart: Int) {
            dismissTagPanel()
            let caretIdx = textView.selectedRange().location
            guard caretIdx > 0 else { return }
            let rect = textView.firstRect(forCharacterRange: NSRange(location: caretIdx, length: 0), actualRange: nil)

            let panel = AutocompletePanel(anchorScreenRect: rect) {
                AutocompleteList(items: suggestions.map { AutocompleteItem(title: "#\($0)", subtitle: nil) }) { [weak self, weak textView] idx in
                    guard let tv = textView, idx < suggestions.count else { return }
                    self?.insertTag(tag: suggestions[idx], textView: tv, replaceStart: replaceStart)
                    self?.dismissTagPanel()
                }
            }
            tagPanel = panel
            panel.show()
        }

        private func dismissWikiPanel() { wikiPanel?.close(); wikiPanel = nil }
        private func dismissTagPanel()  { tagPanel?.close();  tagPanel = nil  }
        private func dismissAll()       { dismissWikiPanel(); dismissTagPanel() }

        // MARK: - Insertion helpers

        private func insertWikiLink(note: Note, textView: NSTextView, replaceStart: Int) {
            let caretIdx = textView.selectedRange().location
            guard replaceStart >= 0, caretIdx >= replaceStart else { return }
            let replaceRange = NSRange(location: replaceStart, length: caretIdx - replaceStart)
            let replacement  = "[[\(note.firstLine)]]"
            if textView.shouldChangeText(in: replaceRange, replacementString: replacement) {
                textView.textStorage?.replaceCharacters(in: replaceRange, with: replacement)
                textView.didChangeText()
                let newCaret = replaceStart + replacement.count
                textView.setSelectedRange(NSRange(location: newCaret, length: 0))
            }
        }

        private func insertTag(tag: String, textView: NSTextView, replaceStart: Int) {
            let caretIdx = textView.selectedRange().location
            guard replaceStart >= 0, caretIdx >= replaceStart else { return }
            let replaceRange = NSRange(location: replaceStart, length: caretIdx - replaceStart)
            let replacement  = "#\(tag) "
            if textView.shouldChangeText(in: replaceRange, replacementString: replacement) {
                textView.textStorage?.replaceCharacters(in: replaceRange, with: replacement)
                textView.didChangeText()
                let newCaret = replaceStart + replacement.count
                textView.setSelectedRange(NSRange(location: newCaret, length: 0))
            }
        }

        // MARK: - Escape key

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                if wikiPanel != nil || tagPanel != nil {
                    dismissAll()
                    return true  // consume the escape
                }
            }
            return false
        }
    }
}

// MARK: - AutocompletePanel

/// A floating NSPanel that hosts a SwiftUI autocomplete list near the cursor.
final class AutocompletePanel: NSPanel {

    init<Content: View>(anchorScreenRect: CGRect, @ViewBuilder content: () -> Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        level           = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 2)
        backgroundColor = .clear
        isOpaque        = false
        hasShadow       = true
        isReleasedWhenClosed = false
        collectionBehavior  = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView:
            content()
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .frame(minWidth: 200, maxWidth: 280)
        )
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting

        // Position below the anchor rect (cursor position)
        let panelH: CGFloat = 200
        setFrameOrigin(NSPoint(
            x: anchorScreenRect.minX,
            y: anchorScreenRect.minY - panelH - 4
        ))
    }

    func show() { orderFront(nil) }
    override var canBecomeKey: Bool { false }  // never steals focus
}

// MARK: - AutocompleteItem / AutocompleteList

struct AutocompleteItem {
    let title: String
    let subtitle: String?
}

struct AutocompleteList: View {
    let items: [AutocompleteItem]
    let onSelect: (Int) -> Void

    @State private var hoveredIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items.indices, id: \.self) { idx in
                Button(action: { onSelect(idx) }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(items[idx].title)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            if let sub = items[idx].subtitle {
                                Text(sub)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(hoveredIndex == idx ? Color.accentColor.opacity(0.15) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in hoveredIndex = inside ? idx : nil }

                if idx < items.count - 1 {
                    Divider().padding(.leading, 10)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Clamp helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif
