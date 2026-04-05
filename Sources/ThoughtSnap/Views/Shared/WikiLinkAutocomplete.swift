#if os(macOS)
import SwiftUI

// MARK: - WikiLinkAutocomplete  (stub — full implementation Week 4)

/// Floating overlay showing note title suggestions after the user types `[[`.
struct WikiLinkAutocomplete: View {
    let suggestions: [Note]
    var onSelect: (Note) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions.prefix(8)) { note in
                Button(action: { onSelect(note) }) {
                    Text(note.firstLine)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect()
            }
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}

// Temporary hover effect shim until AppKit integration is done in Week 4
private extension View {
    func hoverEffect() -> some View {
        self.background(Color.clear)  // placeholder
    }
}
#endif
