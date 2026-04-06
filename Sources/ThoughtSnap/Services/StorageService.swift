#if os(macOS)
import Foundation
import SQLite

// MARK: - StorageError

enum StorageError: Error {
    case databaseNotOpen
    case insertFailed(String)
    case updateFailed(String)
    case deleteFailed(String)
    case fileSystemError(Error)
}

// MARK: - StorageService

/// Manages all persistence: SQLite (notes, FTS5, tags, links) and the file system
/// (screenshot PNGs). Designed to be injected as an @EnvironmentObject.
///
/// Threading model:
///   - writeDB is accessed only on `writeQueue` (serial)
///   - readDB is accessed on the caller's thread (safe under WAL mode)
///   - All public write methods dispatch to writeQueue; callers need not worry about threads
final class StorageService: ObservableObject {

    // MARK: Paths

    static var appSupportDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return base.appendingPathComponent("ThoughtSnap", isDirectory: true)
    }

    /// Root directory used by this instance. Defaults to `appSupportDirectory`; can be
    /// overridden via `init(directory:)` for testing.
    let directory: URL

    private var dbURL: URL {
        directory.appendingPathComponent("thoughtsnap.sqlite")
    }

    // MARK: Connections

    private var writeDB: Connection?
    private var readDB: Connection?
    private let writeQueue = DispatchQueue(label: "com.thoughtsnap.storage.write", qos: .userInitiated)

    // MARK: - Table definitions (SQLite.swift typed columns)

    // notes
    private let notesTable      = Table("notes")
    private let colID           = Expression<String>("id")
    private let colBody         = Expression<String>("body")
    private let colCreatedAt    = Expression<Double>("created_at")
    private let colUpdatedAt    = Expression<Double>("updated_at")
    private let colIsPinned     = Expression<Bool>("is_pinned")
    private let colIsStarred    = Expression<Bool>("is_starred")

    // attachments
    private let attachmentsTable    = Table("attachments")
    private let colNoteID           = Expression<String>("note_id")
    private let colType             = Expression<String>("type")
    private let colFilePath         = Expression<String>("file_path")
    private let colOCRText          = Expression<String?>("ocr_text")

    // annotations
    private let annotationsTable    = Table("annotations")
    private let colAttachmentID     = Expression<String>("attachment_id")
    private let colAnnotationType   = Expression<String>("type")
    private let colX                = Expression<Double>("x")
    private let colY                = Expression<Double>("y")
    private let colWidth            = Expression<Double>("width")
    private let colHeight           = Expression<Double>("height")
    private let colColorHex         = Expression<String>("color_hex")
    private let colLabel            = Expression<String?>("label")
    private let colStrokeWidth      = Expression<Double>("stroke_width")

    // spaces
    private let spacesTable         = Table("spaces")
    private let colName             = Expression<String>("name")
    private let colIcon             = Expression<String?>("icon")
    private let colSortOrder        = Expression<Int>("sort_order")
    private let colIsDefault        = Expression<Bool>("is_default")

    // note_spaces
    private let noteSpacesTable     = Table("note_spaces")
    private let colSpaceID          = Expression<String>("space_id")

    // note_links
    private let noteLinksTable      = Table("note_links")
    private let colSourceID         = Expression<String>("source_id")
    private let colTargetID         = Expression<String>("target_id")

    // tags
    private let tagsTable           = Table("tags")
    private let colTag              = Expression<String>("tag")

    // MARK: - Initialisation

    init() {
        self.directory = Self.appSupportDirectory
        do {
            try setup()
        } catch {
            print("[StorageService] Setup failed: \(error)")
        }
    }

    /// Test-only initializer that stores the database at a custom directory.
    init(directory: URL) {
        self.directory = directory
        do {
            try setup()
        } catch {
            print("[StorageService] Setup failed: \(error)")
        }
    }

    private func setup() throws {
        // Ensure directory exists
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("attachments"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("backups"),
            withIntermediateDirectories: true
        )

        let path = dbURL.path
        writeDB = try Connection(path)
        readDB  = try Connection(path, readonly: true)

        guard let db = writeDB else { return }

        // Performance pragmas
        try db.execute("PRAGMA journal_mode=WAL")
        try db.execute("PRAGMA foreign_keys=ON")
        try db.execute("PRAGMA synchronous=NORMAL")
        try db.execute("PRAGMA cache_size=-8000")  // 8MB page cache

        try createTables(db)
        try createFTSTable(db)
        try createFTSTriggers(db)
        try seedDefaultSpaces(db)
    }

    // MARK: - Schema creation

    private func createTables(_ db: Connection) throws {
        // spaces
        try db.run(spacesTable.create(ifNotExists: true) { t in
            t.column(colID, primaryKey: true)
            t.column(colName)
            t.column(colIcon)
            t.column(colSortOrder, defaultValue: 0)
            t.column(colIsDefault, defaultValue: false)
        })

        // notes
        try db.run(notesTable.create(ifNotExists: true) { t in
            t.column(colID, primaryKey: true)
            t.column(colBody, defaultValue: "")
            t.column(colCreatedAt)
            t.column(colUpdatedAt)
            t.column(colIsPinned, defaultValue: false)
            t.column(colIsStarred, defaultValue: false)
        })

        // attachments
        try db.run(attachmentsTable.create(ifNotExists: true) { t in
            t.column(colID, primaryKey: true)
            t.column(colNoteID, references: notesTable, colID)
            t.column(colType)
            t.column(colFilePath)
            t.column(colOCRText)
            t.column(colCreatedAt)
            t.foreignKey(colNoteID, references: notesTable, colID, delete: .cascade)
        })

        // annotations
        try db.run(annotationsTable.create(ifNotExists: true) { t in
            t.column(colID, primaryKey: true)
            t.column(colAttachmentID)
            t.column(colAnnotationType)
            t.column(colX)
            t.column(colY)
            t.column(colWidth)
            t.column(colHeight)
            t.column(colColorHex)
            t.column(colLabel)
            t.column(colStrokeWidth, defaultValue: 2.0)
            t.foreignKey(colAttachmentID, references: attachmentsTable, colID, delete: .cascade)
        })

        // note_spaces
        try db.run(noteSpacesTable.create(ifNotExists: true) { t in
            t.column(colNoteID)
            t.column(colSpaceID)
            t.primaryKey(colNoteID, colSpaceID)
            t.foreignKey(colNoteID, references: notesTable, colID, delete: .cascade)
            t.foreignKey(colSpaceID, references: spacesTable, colID, delete: .cascade)
        })

        // note_links
        try db.run(noteLinksTable.create(ifNotExists: true) { t in
            t.column(colSourceID)
            t.column(colTargetID)
            t.primaryKey(colSourceID, colTargetID)
            t.foreignKey(colSourceID, references: notesTable, colID, delete: .cascade)
            t.foreignKey(colTargetID, references: notesTable, colID, delete: .cascade)
        })

        // tags
        try db.run(tagsTable.create(ifNotExists: true) { t in
            t.column(colNoteID)
            t.column(colTag)
            t.primaryKey(colNoteID, colTag)
            t.foreignKey(colNoteID, references: notesTable, colID, delete: .cascade)
        })

        // Indexes
        try db.execute("CREATE INDEX IF NOT EXISTS idx_notes_updated ON notes(updated_at DESC)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_notes_pinned ON notes(is_pinned, updated_at DESC)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_tags_tag ON tags(tag)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_attachments_note ON attachments(note_id)")
    }

    // MARK: - FTS5

    private func createFTSTable(_ db: Connection) throws {
        // Contentless FTS5 table — we manage population manually.
        // note_id is UNINDEXED (used for joins, not tokenised).
        try db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
                note_id UNINDEXED,
                body,
                ocr_text,
                annotation_labels,
                tags_blob,
                content='',
                tokenize='unicode61 remove_diacritics 2'
            )
        """)
    }

    private func createFTSTriggers(_ db: Connection) throws {
        // Insert trigger
        try db.execute("""
            CREATE TRIGGER IF NOT EXISTS notes_fts_insert
            AFTER INSERT ON notes BEGIN
                INSERT INTO notes_fts(note_id, body, ocr_text, annotation_labels, tags_blob)
                VALUES (new.id, new.body, '', '', '');
            END
        """)

        // Update trigger (delete old row, insert new)
        try db.execute("""
            CREATE TRIGGER IF NOT EXISTS notes_fts_update
            AFTER UPDATE OF body ON notes BEGIN
                INSERT INTO notes_fts(notes_fts, note_id, body, ocr_text, annotation_labels, tags_blob)
                VALUES ('delete', old.id, old.body, '', '', '');
                INSERT INTO notes_fts(note_id, body, ocr_text, annotation_labels, tags_blob)
                VALUES (new.id, new.body, '', '', '');
            END
        """)

        // Delete trigger
        try db.execute("""
            CREATE TRIGGER IF NOT EXISTS notes_fts_delete
            AFTER DELETE ON notes BEGIN
                INSERT INTO notes_fts(notes_fts, note_id, body, ocr_text, annotation_labels, tags_blob)
                VALUES ('delete', old.id, old.body, '', '', '');
            END
        """)
    }

    // MARK: - Seed default spaces

    private func seedDefaultSpaces(_ db: Connection) throws {
        for space in Space.defaults {
            let existing = try db.scalar(
                spacesTable.filter(colID == space.id.uuidString).count
            )
            guard existing == 0 else { continue }
            try db.run(spacesTable.insert(
                colID       <- space.id.uuidString,
                colName     <- space.name,
                colIcon     <- space.icon,
                colSortOrder <- space.sortOrder,
                colIsDefault <- space.isDefault
            ))
        }
    }

    // MARK: - Notes CRUD

    func saveNote(_ note: Note) -> Result<Void, StorageError> {
        writeQueue.sync {
            guard let db = writeDB else { return .failure(.databaseNotOpen) }
            do {
                let existing = try db.scalar(notesTable.filter(colID == note.id.uuidString).count)
                if existing > 0 {
                    try db.run(
                        notesTable.filter(colID == note.id.uuidString).update(
                            colBody      <- note.body,
                            colUpdatedAt <- note.updatedAt.timeIntervalSince1970,
                            colIsPinned  <- note.isPinned,
                            colIsStarred <- note.isStarred
                        )
                    )
                } else {
                    try db.run(notesTable.insert(
                        colID        <- note.id.uuidString,
                        colBody      <- note.body,
                        colCreatedAt <- note.createdAt.timeIntervalSince1970,
                        colUpdatedAt <- note.updatedAt.timeIntervalSince1970,
                        colIsPinned  <- note.isPinned,
                        colIsStarred <- note.isStarred
                    ))
                }

                // Persist tags
                try db.run(tagsTable.filter(colNoteID == note.id.uuidString).delete())
                for tag in note.tags {
                    try db.run(tagsTable.insert(
                        colNoteID <- note.id.uuidString,
                        colTag    <- tag
                    ))
                }

                // Persist space memberships
                try db.run(noteSpacesTable.filter(colNoteID == note.id.uuidString).delete())
                for spaceID in note.spaceIDs {
                    try db.run(noteSpacesTable.insert(
                        colNoteID  <- note.id.uuidString,
                        colSpaceID <- spaceID.uuidString
                    ))
                }

                return .success(())
            } catch {
                return .failure(.insertFailed(error.localizedDescription))
            }
        }
    }

    func fetchNote(id: UUID) -> Note? {
        guard let db = readDB else { return nil }
        guard let row = try? db.pluck(notesTable.filter(colID == id.uuidString)) else { return nil }
        return noteFromRow(row, db: db)
    }

    func fetchAllNotes(limit: Int = 50, offset: Int = 0, pinnedFirst: Bool = true) -> [Note] {
        guard let db = readDB else { return [] }
        do {
            var query = notesTable
                .order(colUpdatedAt.desc)
                .limit(limit, offset: offset)
            let rows = try db.prepare(query)
            return try rows.compactMap { row in noteFromRow(row, db: db) }
        } catch {
            print("[StorageService] fetchAllNotes error: \(error)")
            return []
        }
    }

    func fetchPinnedNotes() -> [Note] {
        guard let db = readDB else { return [] }
        do {
            let rows = try db.prepare(notesTable.filter(colIsPinned == true).order(colUpdatedAt.desc))
            return rows.compactMap { noteFromRow($0, db: db) }
        } catch { return [] }
    }

    func fetchStarredNotes(limit: Int = 50, offset: Int = 0) -> [Note] {
        guard let db = readDB else { return [] }
        do {
            let rows = try db.prepare(
                notesTable
                    .filter(colIsStarred == true)
                    .order(colUpdatedAt.desc)
                    .limit(limit, offset: offset)
            )
            return rows.compactMap { noteFromRow($0, db: db) }
        } catch { return [] }
    }

    func fetchNotes(inSpace spaceID: UUID, limit: Int = 50, offset: Int = 0) -> [Note] {
        guard let db = readDB else { return [] }
        do {
            // Join notes with note_spaces to filter by space
            let query = """
                SELECT n.id FROM notes n
                JOIN note_spaces ns ON n.id = ns.note_id
                WHERE ns.space_id = ?
                ORDER BY n.updated_at DESC
                LIMIT ? OFFSET ?
            """
            var ids: [UUID] = []
            for row in try db.prepare(query, spaceID.uuidString, limit, offset) {
                if let idStr = row[0] as? String, let id = UUID(uuidString: idStr) {
                    ids.append(id)
                }
            }
            return ids.compactMap { fetchNote(id: $0) }
        } catch { return [] }
    }

    func fetchNotes(withTag tag: String, limit: Int = 50, offset: Int = 0) -> [Note] {
        guard let db = readDB else { return [] }
        do {
            let query = """
                SELECT n.id FROM notes n
                JOIN tags t ON n.id = t.note_id
                WHERE t.tag = ?
                ORDER BY n.updated_at DESC
                LIMIT ? OFFSET ?
            """
            var ids: [UUID] = []
            for row in try db.prepare(query, tag, limit, offset) {
                if let idStr = row[0] as? String, let id = UUID(uuidString: idStr) {
                    ids.append(id)
                }
            }
            return ids.compactMap { fetchNote(id: $0) }
        } catch { return [] }
    }

    func deleteNote(id: UUID) -> Result<Void, StorageError> {
        writeQueue.sync {
            guard let db = writeDB else { return .failure(.databaseNotOpen) }
            do {
                try db.run(notesTable.filter(colID == id.uuidString).delete())
                return .success(())
            } catch {
                return .failure(.deleteFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Attachments

    func saveAttachment(_ attachment: Attachment, for noteID: UUID) -> Result<Void, StorageError> {
        writeQueue.sync {
            guard let db = writeDB else { return .failure(.databaseNotOpen) }
            do {
                try db.run(attachmentsTable.insert(or: .replace,
                    colID       <- attachment.id.uuidString,
                    colNoteID   <- noteID.uuidString,
                    colType     <- attachment.type.rawValue,
                    colFilePath <- attachment.filePath,
                    colOCRText  <- attachment.ocrText,
                    colCreatedAt <- attachment.createdAt.timeIntervalSince1970
                ))
                return .success(())
            } catch {
                return .failure(.insertFailed(error.localizedDescription))
            }
        }
    }

    func updateOCRText(_ text: String, for attachmentID: UUID) {
        writeQueue.async { [weak self] in
            guard let db = self?.writeDB else { return }
            do {
                try db.run(
                    self!.attachmentsTable
                        .filter(self!.colID == attachmentID.uuidString)
                        .update(self!.colOCRText <- text)
                )
                // Update FTS entry with new OCR text
                // We need the note_id to update FTS
                if let row = try? db.pluck(self!.attachmentsTable.filter(self!.colID == attachmentID.uuidString)) {
                    let noteID = row[self!.colNoteID]
                    self?.refreshFTSOCRText(noteID: noteID, ocrText: text, db: db)
                }
            } catch {
                print("[StorageService] updateOCRText error: \(error)")
            }
        }
    }

    private func refreshFTSOCRText(noteID: String, ocrText: String, db: Connection) {
        // Collect all OCR text for this note's attachments
        let allOCR = (try? db.prepare(attachmentsTable.filter(colNoteID == noteID)))
            .flatMap { rows in
                rows.compactMap { $0[colOCRText] }.joined(separator: " ")
            } ?? ocrText

        // Contentless FTS requires delete + insert pattern
        try? db.execute("""
            INSERT INTO notes_fts(notes_fts, note_id, body, ocr_text, annotation_labels, tags_blob)
            SELECT 'delete', note_id, body, ocr_text, annotation_labels, tags_blob
            FROM notes_fts WHERE note_id = '\(noteID)'
        """)
        try? db.execute("""
            INSERT INTO notes_fts(note_id, body, ocr_text, annotation_labels, tags_blob)
            SELECT note_id, body, '\(allOCR.replacingOccurrences(of: "'", with: "''"))', annotation_labels, tags_blob
            FROM notes_fts WHERE note_id = '\(noteID)'
        """)
    }

    // MARK: - Annotations

    func saveAnnotations(_ annotations: [Annotation], for attachmentID: UUID) -> Result<Void, StorageError> {
        writeQueue.sync {
            guard let db = writeDB else { return .failure(.databaseNotOpen) }
            do {
                try db.run(annotationsTable.filter(colAttachmentID == attachmentID.uuidString).delete())
                for ann in annotations {
                    try db.run(annotationsTable.insert(
                        colID              <- ann.id.uuidString,
                        colAttachmentID    <- attachmentID.uuidString,
                        colAnnotationType  <- ann.type.rawValue,
                        colX               <- ann.x,
                        colY               <- ann.y,
                        colWidth           <- ann.width,
                        colHeight          <- ann.height,
                        colColorHex        <- ann.colorHex,
                        colLabel           <- ann.label,
                        colStrokeWidth     <- ann.strokeWidth
                    ))
                }
                return .success(())
            } catch {
                return .failure(.insertFailed(error.localizedDescription))
            }
        }
    }

    func fetchAnnotations(for attachmentID: UUID) -> [Annotation] {
        guard let db = readDB else { return [] }
        do {
            let rows = try db.prepare(annotationsTable.filter(colAttachmentID == attachmentID.uuidString))
            return rows.compactMap { row -> Annotation? in
                guard let type = Annotation.AnnotationType(rawValue: row[colAnnotationType]) else { return nil }
                return Annotation(
                    id: UUID(uuidString: row[colID]) ?? UUID(),
                    type: type,
                    x: row[colX],
                    y: row[colY],
                    width: row[colWidth],
                    height: row[colHeight],
                    colorHex: row[colColorHex],
                    label: row[colLabel],
                    strokeWidth: row[colStrokeWidth]
                )
            }
        } catch { return [] }
    }

    // MARK: - Spaces

    func fetchSpaces() -> [Space] {
        guard let db = readDB else { return Space.defaults }
        do {
            let rows = try db.prepare(spacesTable.order(colSortOrder))
            return rows.map { row in
                Space(
                    id: UUID(uuidString: row[colID]) ?? UUID(),
                    name: row[colName],
                    icon: row[colIcon],
                    sortOrder: row[colSortOrder],
                    isDefault: row[colIsDefault]
                )
            }
        } catch { return Space.defaults }
    }

    func saveSpace(_ space: Space) -> Result<Void, StorageError> {
        writeQueue.sync {
            guard let db = writeDB else { return .failure(.databaseNotOpen) }
            do {
                try db.run(spacesTable.insert(or: .replace,
                    colID        <- space.id.uuidString,
                    colName      <- space.name,
                    colIcon      <- space.icon,
                    colSortOrder <- space.sortOrder,
                    colIsDefault <- space.isDefault
                ))
                return .success(())
            } catch {
                return .failure(.insertFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Note links

    func saveLinks(sourceID: UUID, targetIDs: [UUID]) -> Result<Void, StorageError> {
        writeQueue.sync {
            guard let db = writeDB else { return .failure(.databaseNotOpen) }
            do {
                try db.run(noteLinksTable.filter(colSourceID == sourceID.uuidString).delete())
                for targetID in targetIDs {
                    try db.run(noteLinksTable.insert(
                        colSourceID <- sourceID.uuidString,
                        colTargetID <- targetID.uuidString
                    ))
                }
                return .success(())
            } catch {
                return .failure(.insertFailed(error.localizedDescription))
            }
        }
    }

    func fetchBacklinks(for noteID: UUID) -> [UUID] {
        guard let db = readDB else { return [] }
        do {
            let rows = try db.prepare(noteLinksTable.filter(colTargetID == noteID.uuidString))
            return rows.compactMap { UUID(uuidString: $0[colSourceID]) }
        } catch { return [] }
    }

    // MARK: - Tags

    /// Returns the set of note IDs that carry a specific tag.
    func fetchNoteIDs(forTag tag: String) -> Set<UUID> {
        guard let db = readDB else { return [] }
        do {
            let rows = try db.prepare(tagsTable.filter(colTag == tag).select(colNoteID))
            return Set(rows.compactMap { UUID(uuidString: $0[colNoteID]) })
        } catch { return [] }
    }

    func fetchAllTags() -> [String] {
        guard let db = readDB else { return [] }
        do {
            let rows = try db.prepare(
                tagsTable
                    .select(colTag)
                    .group(colTag)
                    .order(colTag)
            )
            return rows.map { $0[colTag] }
        } catch { return [] }
    }

    // MARK: - FTS search (raw SQL — SQLite.swift has no native FTS5 API)

    func searchNotes(query: String) -> [(noteID: UUID, snippet: String)] {
        guard let db = readDB, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        // Escape FTS5 special characters
        let escaped = query
            .replacingOccurrences(of: "\"", with: "\"\"")
        let ftsQuery = "\"\(escaped)\""

        do {
            var results: [(UUID, String)] = []
            let stmt = try db.prepare("""
                SELECT note_id,
                       snippet(notes_fts, 1, '<b>', '</b>', '…', 32)
                FROM notes_fts
                WHERE notes_fts MATCH ?
                ORDER BY bm25(notes_fts)
                LIMIT 100
            """, ftsQuery)

            for row in stmt {
                if let idStr = row[0] as? String,
                   let id = UUID(uuidString: idStr),
                   let snippet = row[1] as? String {
                    results.append((id, snippet))
                }
            }
            return results
        } catch {
            print("[StorageService] searchNotes error: \(error)")
            return []
        }
    }

    // MARK: - FTS annotation labels update

    /// Called after annotations are persisted to update the FTS index with text labels.
    /// Text annotation labels become full-text-searchable, so a search for a word
    /// drawn on a screenshot will find the containing note.
    func updateFTSAnnotationLabels(noteID: UUID, labels: String) {
        writeQueue.async { [weak self] in
            guard let self, let db = self.writeDB else { return }
            let id = noteID.uuidString
            let escaped = labels.replacingOccurrences(of: "'", with: "''")
            // Contentless FTS5: delete existing row, insert updated row
            try? db.execute("""
                INSERT INTO notes_fts(notes_fts, note_id, body, ocr_text, annotation_labels, tags_blob)
                SELECT 'delete', note_id, body, ocr_text, annotation_labels, tags_blob
                FROM notes_fts WHERE note_id = '\(id)'
            """)
            try? db.execute("""
                INSERT INTO notes_fts(note_id, body, ocr_text, annotation_labels, tags_blob)
                SELECT note_id, body, ocr_text, '\(escaped)', tags_blob
                FROM notes_fts WHERE note_id = '\(id)'
            """)
        }
    }

    // MARK: - File system helpers

    func attachmentDirectory(for date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let monthDir = formatter.string(from: date)
        let dir = Self.appSupportDirectory
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent(monthDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Private helpers

    private func noteFromRow(_ row: Row, db: Connection) -> Note? {
        guard let id = UUID(uuidString: row[colID]) else { return nil }

        // Fetch tags
        let tags = (try? db.prepare(tagsTable.filter(colNoteID == row[colID])))
            .flatMap { rows in rows.map { $0[colTag] } } ?? []

        // Fetch space IDs
        let spaceIDs = (try? db.prepare(noteSpacesTable.filter(colNoteID == row[colID])))
            .flatMap { rows in rows.compactMap { UUID(uuidString: $0[colSpaceID]) } } ?? []

        // Fetch link targets
        let linksTo = (try? db.prepare(noteLinksTable.filter(colSourceID == row[colID])))
            .flatMap { rows in rows.compactMap { UUID(uuidString: $0[colTargetID]) } } ?? []

        // Fetch attachments
        let attachments = fetchAttachments(for: id, db: db)

        return Note(
            id: id,
            body: row[colBody],
            createdAt: Date(timeIntervalSince1970: row[colCreatedAt]),
            updatedAt: Date(timeIntervalSince1970: row[colUpdatedAt]),
            isPinned: row[colIsPinned],
            isStarred: row[colIsStarred],
            spaceIDs: spaceIDs,
            attachments: attachments,
            linksTo: linksTo,
            tags: tags
        )
    }

    private func fetchAttachments(for noteID: UUID, db: Connection) -> [Attachment] {
        guard let rows = try? db.prepare(
            attachmentsTable
                .filter(colNoteID == noteID.uuidString)
                .order(colCreatedAt)
        ) else { return [] }

        return rows.compactMap { row -> Attachment? in
            guard let id = UUID(uuidString: row[colID]),
                  let type = Attachment.AttachmentType(rawValue: row[colType])
            else { return nil }

            let annotations = fetchAnnotations(for: id)

            return Attachment(
                id: id,
                type: type,
                filePath: row[colFilePath],
                annotations: annotations,
                ocrText: row[colOCRText],
                createdAt: Date(timeIntervalSince1970: row[colCreatedAt])
            )
        }
    }
}
#endif
