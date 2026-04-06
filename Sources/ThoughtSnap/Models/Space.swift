#if os(macOS)
import Foundation

// MARK: - Space

/// Lightweight grouping for notes. A note can belong to multiple Spaces.
struct Space: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// SF Symbol name or emoji
    var icon: String?
    var sortOrder: Int
    /// True for built-in spaces (Inbox, Archive) that cannot be deleted
    var isDefault: Bool

    init(
        id: UUID = UUID(),
        name: String,
        icon: String? = nil,
        sortOrder: Int = 0,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
        self.isDefault = isDefault
    }
}

// MARK: - Built-in spaces

extension Space {
    static let inbox = Space(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Inbox",
        icon: "tray",
        sortOrder: 0,
        isDefault: true
    )

    static let archive = Space(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Archive",
        icon: "archivebox",
        sortOrder: 1,
        isDefault: true
    )

    static var defaults: [Space] { [.inbox, .archive] }
}
#endif
