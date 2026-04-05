#if os(macOS)
import SwiftUI

// MARK: - NoteDetailView  (stub — full implementation Week 5)

struct NoteDetailView: View {
    let note: Note

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(note.body)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .padding()
            }
        }
        .navigationTitle(note.firstLine)
    }
}
#endif
