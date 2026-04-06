#if os(macOS)
import Foundation
import Combine

// MARK: - LinkGraphService

/// Maintains the wiki-link graph between notes.
///
/// On every save:
///   1. Extract [[wiki link]] titles from the note body
///   2. Resolve titles → UUIDs via case-insensitive firstLine match
///   3. Create stub notes for unresolved titles (auto-create behaviour)
///   4. Persist edges to note_links table
///   5. Rebuild backlinkMap from the full link table
///
/// `backlinkMap` is @Published so NoteDetailView updates reactively.
final class LinkGraphService: ObservableObject {

    @Published private(set) var backlinkMap: [UUID: [Note]] = [:]

    private let storageService: StorageService

    init(storageService: StorageService) {
        self.storageService = storageService
    }

    // MARK: - Process links on save

    /// Call this after saving a note. Extracts links, resolves/creates targets,
    /// persists edges, and refreshes the backlink map.
    func processLinks(for note: Note) {
        let titles = Note.extractWikiLinks(from: note.body)
        guard !titles.isEmpty else {
            // Still clear any stale links for this note
            _ = storageService.saveLinks(sourceID: note.id, targetIDs: [])
            refreshBacklinkMap()
            return
        }

        let allNotes = storageService.fetchAllNotes(limit: 10_000, offset: 0)
        var resolved: [UUID] = []

        for title in titles {
            if let existing = allNotes.first(where: {
                $0.firstLine.localizedCaseInsensitiveCompare(title) == .orderedSame
            }) {
                resolved.append(existing.id)
            } else {
                // Auto-create a stub note so the link isn't dangling
                let stub = makeStub(title: title)
                _ = storageService.saveNote(stub)
                resolved.append(stub.id)
            }
        }

        _ = storageService.saveLinks(sourceID: note.id, targetIDs: resolved)
        refreshBacklinkMap()
    }

    // MARK: - Backlinks query

    /// Returns notes that link TO the given note ID.
    func backlinks(for noteID: UUID) -> [Note] {
        backlinkMap[noteID] ?? []
    }

    // MARK: - Refresh

    /// Recomputes the full backlink map from the note_links table.
    /// Runs on a background queue; publishes on main.
    func refreshBacklinkMap() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let allNotes = self.storageService.fetchAllNotes(limit: 10_000, offset: 0)
            var map: [UUID: [Note]] = [:]

            for note in allNotes {
                for targetID in note.linksTo {
                    map[targetID, default: []].append(note)
                }
            }

            DispatchQueue.main.async { self.backlinkMap = map }
        }
    }

    // MARK: - Resolution helpers

    /// Resolves a list of [[titles]] to Note UUIDs against a known notes array.
    func resolveLinks(_ titles: [String], in notes: [Note]) -> [UUID] {
        titles.compactMap { title in
            notes.first { $0.firstLine.localizedCaseInsensitiveCompare(title) == .orderedSame }?.id
        }
    }

    // MARK: - Stub creation

    private func makeStub(title: String) -> Note {
        var stub = Note.empty()
        stub.body     = title   // first line = title
        stub.spaceIDs = [Space.inbox.id]
        return stub
    }
}
#endif
