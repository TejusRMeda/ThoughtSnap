#if os(macOS)
import Foundation
import Combine

// MARK: - TimelineFilter

/// What the timeline is currently showing.
enum TimelineFilter: Equatable, Hashable {
    case all
    case starred
    case pinned
    case space(Space)
    case tag(String)

    var displayName: String {
        switch self {
        case .all:         return "All Notes"
        case .starred:     return "Starred"
        case .pinned:      return "Pinned"
        case .space(let s): return s.name
        case .tag(let t):  return "#\(t)"
        }
    }

    var systemImage: String {
        switch self {
        case .all:     return "tray.2"
        case .starred: return "star"
        case .pinned:  return "pin"
        case .space:   return "folder"
        case .tag:     return "number"
        }
    }
}

// MARK: - MainWindowViewModel

/// Shared state driving the three-column main window layout.
/// Injected as @StateObject from MainWindowController; observed by all columns.
final class MainWindowViewModel: ObservableObject {

    // MARK: Navigation state

    @Published var selectedFilter: TimelineFilter = .all
    @Published var selectedNoteID: UUID? = nil
    @Published var searchQuery:    String = ""

    // MARK: Derived

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Actions

    func select(note: Note) {
        selectedNoteID = note.id
    }

    func clearSearch() {
        searchQuery = ""
    }

    func apply(filter: TimelineFilter) {
        selectedFilter = filter
        selectedNoteID = nil
        clearSearch()
    }
}
#endif
