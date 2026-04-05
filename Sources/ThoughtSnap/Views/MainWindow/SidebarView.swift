#if os(macOS)
import SwiftUI

// MARK: - SidebarView  (stub — full implementation Week 5)

struct SidebarView: View {
    @EnvironmentObject var storageService: StorageService

    var body: some View {
        List {
            Section("Spaces") {
                ForEach(storageService.fetchSpaces()) { space in
                    Label(space.name, systemImage: space.icon ?? "folder")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ThoughtSnap")
    }
}
#endif
