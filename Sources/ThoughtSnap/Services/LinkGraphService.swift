#if os(macOS)
import Foundation
import Combine

// MARK: - LinkGraphService
// Full implementation in Week 4.

final class LinkGraphService: ObservableObject {

    @Published private(set) var backlinkMap: [UUID: [Note]] = [:]

    private let storageService: StorageService

    init(storageService: StorageService) {
        self.storageService = storageService
    }

    /// Extracts [[wiki links]] from `body`, resolves titles to UUIDs,
    /// persists to the note_links table, and refreshes backlinkMap.
    func processLinks(for note: Note, allNotes: [Note]) {
        let titles   = Note.extractWikiLinks(from: note.body)
        let resolved = resolveLinks(titles, in: allNotes)
        _ = storageService.saveLinks(sourceID: note.id, targetIDs: resolved)
        refreshBacklinkMap(allNotes: allNotes)
    }

    func backlinks(for noteID: UUID) -> [Note] {
        backlinkMap[noteID] ?? []
    }

    // MARK: - Private

    private func resolveLinks(_ titles: [String], in notes: [Note]) -> [UUID] {
        titles.compactMap { title in
            notes.first { $0.firstLine.localizedCaseInsensitiveCompare(title) == .orderedSame }?.id
        }
    }

    private func refreshBacklinkMap(allNotes: [Note]) {
        var map: [UUID: [Note]] = [:]
        for note in allNotes {
            for targetID in note.linksTo {
                map[targetID, default: []].append(note)
            }
        }
        DispatchQueue.main.async { self.backlinkMap = map }
    }
}
#endif
