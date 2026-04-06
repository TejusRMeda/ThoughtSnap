#if os(macOS)
import SwiftUI
import AppKit
import Combine

// MARK: - NoteDetailViewModel

final class NoteDetailViewModel: ObservableObject {

    @Published var note:      Note
    @Published var isEditing  = false
    @Published var editBody   = ""
    @Published var isSaving   = false

    private let storageService: StorageService
    private let linkService:    LinkGraphService
    private var autoSaveTask:   Task<Void, Never>?

    init(note: Note, storageService: StorageService, linkService: LinkGraphService) {
        self.note           = note
        self.storageService = storageService
        self.linkService    = linkService
        self.editBody       = note.body
    }

    func enterEditMode() {
        editBody  = note.body
        isEditing = true
    }

    func exitEditMode(save: Bool) {
        if save { commitSave() }
        isEditing = false
        autoSaveTask?.cancel()
    }

    /// Schedules auto-save 1 s after the last keystroke.
    func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            commitSave()
        }
    }

    func commitSave() {
        var updated       = note
        updated.body      = editBody
        updated.updatedAt = Date()
        updated.tags      = Note.extractTags(from: editBody)
        if updated.spaceIDs.isEmpty { updated.spaceIDs = [Space.inbox.id] }

        isSaving = true
        _ = storageService.saveNote(updated)
        linkService.processLinks(for: updated)
        note     = updated
        isSaving = false
    }
}

// MARK: - NoteDetailContainerView
//
// Outer container that owns the NoteDetailViewModel as a @StateObject.
// Re-creates the view model when noteID changes by using `.id(noteID)`.
struct NoteDetailContainerView: View {
    let noteID: UUID

    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var linkService:    LinkGraphService
    @EnvironmentObject var windowVM:       MainWindowViewModel

    var body: some View {
        if let note = storageService.fetchNote(id: noteID) {
            NoteDetailView(
                initialNote: note,
                storageService: storageService,
                linkService: linkService
            )
            .id(noteID)          // forces full re-init when note changes
            .environmentObject(windowVM)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Note not found")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - NoteDetailView

struct NoteDetailView: View {

    @StateObject private var vm: NoteDetailViewModel
    @EnvironmentObject var windowVM: MainWindowViewModel

    private let storageService: StorageService
    private let linkService:    LinkGraphService

    init(initialNote: Note, storageService: StorageService, linkService: LinkGraphService) {
        self.storageService = storageService
        self.linkService    = linkService
        _vm = StateObject(wrappedValue: NoteDetailViewModel(
            note: initialNote,
            storageService: storageService,
            linkService: linkService
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !vm.note.attachments.isEmpty {
                attachmentStrip
                Divider()
            }

            if vm.isEditing {
                editBody
            } else {
                readBody
            }

            backlinkSection
        }
        .navigationTitle(vm.note.firstLine)
        .toolbar { toolbarItems }
        .onAppear { linkService.refreshBacklinkMap() }
    }

    // MARK: Attachment strip

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.note.attachments) { AttachmentTile(attachment: $0) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(height: 80)
        .background(AppTheme.secondaryBackground)
    }

    // MARK: Read mode

    private var readBody: some View {
        ScrollView {
            RenderedMarkdownView(body: vm.note.body)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onTapGesture(count: 2) { vm.enterEditMode() }
    }

    // MARK: Edit mode

    private var editBody: some View {
        VStack(spacing: 0) {
            MarkdownEditor(
                text: Binding(
                    get:  { vm.editBody },
                    set:  { vm.editBody = $0; vm.scheduleAutoSave() }
                ),
                allNotes: storageService.fetchAllNotes(limit: 200, offset: 0),
                allTags:  storageService.fetchAllTags()
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Tag preview + save indicator
            let liveTags = Note.extractTags(from: vm.editBody)
            if !liveTags.isEmpty || vm.isSaving {
                Divider()
                HStack(spacing: 6) {
                    if !liveTags.isEmpty {
                        Image(systemName: "number")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                        ForEach(liveTags, id: \.self) { TagView(tag: $0) }
                    }
                    Spacer()
                    saveIndicator
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.secondaryBackground)
            }
        }
    }

    @ViewBuilder
    private var saveIndicator: some View {
        if vm.isSaving {
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6)
                Text("Saving…").font(.system(size: 11)).foregroundStyle(AppTheme.tertiaryLabel)
            }
        } else {
            Text("Auto-saved").font(.system(size: 11)).foregroundStyle(AppTheme.tertiaryLabel)
        }
    }

    // MARK: Backlinks

    @ViewBuilder
    private var backlinkSection: some View {
        let backlinks = linkService.backlinks(for: vm.note.id)
        if !backlinks.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Referenced by \(backlinks.count) note\(backlinks.count == 1 ? "" : "s")",
                    systemImage: "arrow.backward"
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryLabel)

                ForEach(backlinks.prefix(5)) { source in
                    Button(action: { windowVM.selectedNoteID = source.id }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.secondaryLabel)
                            Text(source.firstLine)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }

                if backlinks.count > 5 {
                    Text("+ \(backlinks.count - 5) more")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AppTheme.secondaryBackground)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if vm.isEditing {
                Button("Done") { vm.exitEditMode(save: true) }
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button { vm.enterEditMode() } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .help("Edit note — or double-click body")

                Menu {
                    Button(action: togglePin)  {
                        Label(vm.note.isPinned  ? "Unpin"   : "Pin",
                              systemImage: vm.note.isPinned  ? "pin.slash" : "pin")
                    }
                    Button(action: toggleStar) {
                        Label(vm.note.isStarred ? "Unstar"  : "Star",
                              systemImage: vm.note.isStarred ? "star.slash" : "star")
                    }
                    Divider()
                    Button(role: .destructive, action: deleteNote) {
                        Label("Delete Note", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: Actions

    private func togglePin() {
        var n = vm.note; n.isPinned.toggle()
        _ = storageService.saveNote(n); vm.note = n
    }
    private func toggleStar() {
        var n = vm.note; n.isStarred.toggle()
        _ = storageService.saveNote(n); vm.note = n
    }
    private func deleteNote() {
        _ = storageService.deleteNote(id: vm.note.id)
        windowVM.selectedNoteID = nil
    }
}

// MARK: - RenderedMarkdownView

struct RenderedMarkdownView: NSViewRepresentable {
    let body: String

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSTextView.scrollableTextView()
        guard let tv = sv.documentView as? NSTextView else { return sv }
        tv.isEditable         = false
        tv.isSelectable       = true
        tv.drawsBackground    = false
        tv.backgroundColor    = .clear
        tv.textContainerInset = NSSize(width: 0, height: 0)
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? NSTextView else { return }
        let rendered = MarkdownParser.render(body)
        tv.textStorage?.setAttributedString(rendered)
    }
}

// MARK: - AttachmentTile

struct AttachmentTile: View {
    let attachment: Attachment
    @State private var thumbnail: NSImage? = nil
    @State private var isExpanded = false

    var body: some View {
        Button(action: { isExpanded = true }) {
            Group {
                if let img = thumbnail {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    AppTheme.secondaryBackground
                        .overlay(Image(systemName: "photo").foregroundStyle(AppTheme.tertiaryLabel))
                }
            }
            .frame(width: 64, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            DispatchQueue.global(qos: .utility).async {
                let img = NSImage(contentsOf: attachment.thumbnailURL)
                    ?? NSImage(contentsOf: attachment.absoluteFileURL)
                DispatchQueue.main.async { thumbnail = img }
            }
        }
        .sheet(isPresented: $isExpanded) { expandedSheet }
    }

    private var expandedSheet: some View {
        VStack(spacing: 0) {
            if let img = NSImage(contentsOf: attachment.absoluteFileURL) {
                // Read-only view of the annotated screenshot
                AnnotatedScreenshotView(
                    image: img,
                    annotations:  .constant(attachment.annotations),
                    activeTool:   .constant(.arrow),
                    activeColor:  .constant(.systemRed),
                    strokeWidth:  .constant(2.5)
                )
            } else {
                Text("Image not found").foregroundStyle(.secondary).padding()
            }
            Divider()
            Button("Close") { isExpanded = false }
                .keyboardShortcut(.escape, modifiers: [])
                .padding(12)
        }
        .frame(minWidth: 640, minHeight: 500)
    }
}
#endif
