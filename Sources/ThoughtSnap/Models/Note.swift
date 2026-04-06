#if os(macOS)
import Foundation

// MARK: - Note

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var isStarred: Bool
    var spaceIDs: [UUID]
    var attachments: [Attachment]
    var linksTo: [UUID]       // outgoing [[wiki links]], resolved to UUIDs
    var tags: [String]        // extracted from #hashtags in body

    init(
        id: UUID = UUID(),
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        isStarred: Bool = false,
        spaceIDs: [UUID] = [],
        attachments: [Attachment] = [],
        linksTo: [UUID] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.isStarred = isStarred
        self.spaceIDs = spaceIDs
        self.attachments = attachments
        self.linksTo = linksTo
        self.tags = tags
    }

    static func empty() -> Note {
        Note()
    }
}

// MARK: - Computed properties

extension Note {
    /// First non-blank line of body — used as the note's display title.
    var firstLine: String {
        body
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces)
            ?? "Untitled"
    }

    /// First 160 characters of body (after the first line), used in search result previews.
    var excerpt: String {
        let lines = body.components(separatedBy: .newlines)
        let rest = lines.dropFirst().joined(separator: " ")
        let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.count > 160 ? String(trimmed.prefix(160)) + "…" : trimmed
    }

    /// Whether the note has any screenshot attachments.
    var hasScreenshots: Bool {
        attachments.contains { $0.type == .screenshot }
    }
}

// MARK: - Tag and wiki-link extraction

extension Note {
    /// Extracts `#tag` tokens from a Markdown body string.
    /// Rules:
    ///   - Must be preceded by whitespace or start-of-string (not a Markdown heading `#`)
    ///   - Tag characters: word characters and hyphens
    static func extractTags(from body: String) -> [String] {
        // Regex: (^|\\s)#([\\w-]+)
        // Capture group 2 is the tag name without the leading #
        let pattern = #"(?:^|\s)#([\w-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return []
        }
        let nsBody = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
        return matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1 else { return nil }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { return nil }
            return nsBody.substring(with: range).lowercased()
        }
    }

    /// Extracts `[[note title]]` link targets from a Markdown body string.
    /// Returns raw title strings (not yet resolved to UUIDs).
    static func extractWikiLinks(from body: String) -> [String] {
        let pattern = #"\[\[(.+?)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsBody = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
        return matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1 else { return nil }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { return nil }
            return nsBody.substring(with: range)
        }
    }
}
#endif
