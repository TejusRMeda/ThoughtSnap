#if os(macOS)
import SwiftUI

// MARK: - WikiLinkAutocomplete
//
// This view is the standalone Shared autocomplete used by NoteDetailView.
// The MarkdownEditor uses AutocompletePanel/AutocompleteList directly for
// cursor-positioned floating panels (see MarkdownEditor.swift).

struct WikiLinkAutocomplete: View {
    let suggestions: [Note]
    var query: String = ""
    var onSelect: (Note) -> Void
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions.prefix(8)) { note in
                Button(action: { onSelect(note) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            // Highlight matched portion in the title
                            highlightedTitle(note.firstLine, query: query)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            if !note.excerpt.isEmpty {
                                Text(note.excerpt)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.clear)

                if note.id != suggestions.prefix(8).last?.id {
                    Divider().padding(.leading, 30)
                }
            }
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Highlighted title

    private func highlightedTitle(_ title: String, query: String) -> some View {
        guard !query.isEmpty,
              let range = title.range(of: query, options: .caseInsensitive)
        else {
            return Text(title).foregroundStyle(Color(NSColor.labelColor))
        }

        let before = String(title[title.startIndex..<range.lowerBound])
        let match  = String(title[range])
        let after  = String(title[range.upperBound...])

        return Text(before)
            + Text(match).bold().foregroundStyle(Color.accentColor)
            + Text(after)
    }
}
#endif
