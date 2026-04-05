#if os(macOS)
import SwiftUI

// MARK: - TimelineView  (stub — full implementation Week 5)

struct TimelineView: View {
    @EnvironmentObject var storageService: StorageService
    @State private var notes: [Note] = []

    var body: some View {
        List(notes) { note in
            VStack(alignment: .leading, spacing: 4) {
                Text(note.firstLine)
                    .font(.system(size: 13, weight: .medium))
                if !note.excerpt.isEmpty {
                    Text(note.excerpt)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !note.tags.isEmpty {
                    HStack {
                        ForEach(note.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 10))
                                .foregroundStyle(.accentColor)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear { notes = storageService.fetchAllNotes() }
        .navigationTitle("ThoughtSnap")
    }
}
#endif
