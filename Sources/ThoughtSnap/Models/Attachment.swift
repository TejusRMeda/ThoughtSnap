#if os(macOS)
import Foundation

// MARK: - Attachment

struct Attachment: Identifiable, Codable, Equatable {
    let id: UUID
    var type: AttachmentType
    /// Path relative to the ThoughtSnap Application Support directory.
    /// e.g. "attachments/2026-04/{uuid}.png"
    var filePath: String
    var annotations: [Annotation]
    var ocrText: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        type: AttachmentType,
        filePath: String,
        annotations: [Annotation] = [],
        ocrText: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.filePath = filePath
        self.annotations = annotations
        self.ocrText = ocrText
        self.createdAt = createdAt
    }
}

// MARK: - AttachmentType

extension Attachment {
    enum AttachmentType: String, Codable, Equatable {
        case screenshot
        case image
        case audio
    }
}

// MARK: - Computed paths

extension Attachment {
    /// Absolute URL constructed from the relative `filePath` + the app's support directory.
    var absoluteFileURL: URL {
        Self.appSupportDirectory.appendingPathComponent(filePath)
    }

    /// Thumbnail URL — same directory as the original, with `-thumb` suffix.
    var thumbnailURL: URL {
        let base = absoluteFileURL.deletingPathExtension()
        let ext  = absoluteFileURL.pathExtension
        return base.appendingPathExtension("thumb").appendingPathExtension(ext)
    }

    static var appSupportDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return base.appendingPathComponent("ThoughtSnap", isDirectory: true)
    }
}
#endif
