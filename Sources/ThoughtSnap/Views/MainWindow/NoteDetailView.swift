#if os(macOS)
import SwiftUI
import AppKit
import Combine

// MARK: - NoteDetailViewModel

final class NoteDetailViewModel: ObservableObject {

    @Published var note: Note
    @Published var isEditing = false
    @Published var editBody  = ""
    @Published var isSaving  = false

    private let storageService: StorageService
    private let linkService:    LinkGraphService
    private var autoSaveTask:   Task<Void, Never>?

    init(note: Note, storageService: StorageService, linkService: LinkGraphService) {
        self.note          = note
        self.storageService = storageService
        self.linkService    = linkService
        self.editBody       = note.body
    }

    // MARK: - Edit / Save

    func enterEditMode() {
        editBody  = note.body
        isEditing = true
    }

    func exitEditMode(save: Bool) {
        if save { commitSave() }
        isEditing = false
        autoSaveTask?.cancel()
    }

    /// Schedules an auto-save 1s after the last keystroke.
    func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            commitSave()
        }
    }

    private func commitSave() {
        var updated        = note
        updated.body       = editBody
        updated.updatedAt  = Date()
        updated.tags       = Note.extractTags(from: editBody)
        updated.spaceIDs   = note.spaceIDs.isEmpty ? [Space.inbox.id] : note.spaceIDs

        isSaving = true
        _ = storageService.saveNote(updated)
        linkService.processLinks(for: updated)
        note    = updated
        isSaving = false
    }
}

// MARK: - NoteDetailView

/// Right-most column of the main window.
///
/// Read mode:  Rendered Markdown (MarkdownParser.render)
/// Edit mode:  MarkdownEditor (live syntax highlight + autocomplete)
/// Toggle:     Double-click body OR ✎ Edit button in toolbar
/// Auto-save:  1 second after last keystroke in edit mode
struct NoteDetailView: View {

    let noteID: UUID

    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var windowVM:       MainWindowViewModel
    @StateObject private var linkService:  LinkGraphService = LinkGraphService(storageService: StorageService())

    @State private var viewModel: NoteDetailViewModel? = nil

    var body: some View {
        Group {
            if let vm = viewModel {
                noteContent(vm: vm)
            } else {
                emptyState
            }
        }
        .onAppear { loadNote() }
        .onChange(of: noteID) { _ in loadNote() }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Select a note")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Note content

    private func noteContent(vm: NoteDetailViewModel) -> some View {
        VStack(spacing: 0) {
            // Attachment strip
            if !vm.note.attachments.isEmpty {
                attachmentStrip(vm: vm)
                Divider()
            }

            // Body
            if vm.isEditing {
                editBody(vm: vm)
            } else {
                readBody(vm: vm)
            }

            // Backlinks section
            backlinkSection(vm: vm)
        }
        .navigationTitle(vm.note.firstLine)
        .toolbar { toolbarItems(vm: vm) }
    }

    // MARK: - Attachment strip

    private func attachmentStrip(vm: NoteDetailViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.note.attachments) { attachment in
                    AttachmentTile(attachment: attachment)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(height: 80)
    }

    // MARK: - Read mode

    private func readBody(vm: NoteDetailViewModel) -> some View {
        ScrollView {
            RenderedMarkdownView(body: vm.note.body)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onTapGesture(count: 2) { vm.enterEditMode() }
    }

    // MARK: - Edit mode

    private func editBody(vm: NoteDetailViewModel) -> some View {
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

            // Tags preview while editing
            if !Note.extractTags(from: vm.editBody).isEmpty {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "number")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    ForEach(Note.extractTags(from: vm.editBody), id: \.self) { tag in
                        TagView(tag: tag)
                    }
                    Spacer()
                    if vm.isSaving {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(vm.isSaving ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false),
                                       value: vm.isSaving)
                    } else {
                        Text("Saved")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Backlinks

    private func backlinkSection(vm: NoteDetailViewModel) -> some View {
        let backlinks = linkService.backlinks(for: vm.note.id)
        return Group {
            if !backlinks.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Referenced by \(backlinks.count) note\(backlinks.count == 1 ? "" : "s")",
                          systemImage: "arrow.backward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(backlinks.prefix(5)) { source in
                        Button(action: { windowVM.selectedNoteID = source.id }) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
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
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarItems(vm: NoteDetailViewModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if vm.isEditing {
                Button("Done") { vm.exitEditMode(save: true) }
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button(action: { vm.enterEditMode() }) {
                    Label("Edit", systemImage: "pencil")
                }
                .help("Edit note (double-click body)")

                Menu {
                    Button(action: togglePin(vm: vm)) {
                        Label(vm.note.isPinned ? "Unpin" : "Pin",
                              systemImage: vm.note.isPinned ? "pin.slash" : "pin")
                    }
                    Button(action: toggleStar(vm: vm)) {
                        Label(vm.note.isStarred ? "Unstar" : "Star",
                              systemImage: vm.note.isStarred ? "star.slash" : "star")
                    }
                    Divider()
                    Button(role: .destructive, action: { deleteNote(vm: vm) }) {
                        Label("Delete Note", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Actions

    private func loadNote() {
        guard let note = storageService.fetchNote(id: noteID) else { return }
        let ls = LinkGraphService(storageService: storageService)
        ls.refreshBacklinkMap()
        viewModel = NoteDetailViewModel(note: note, storageService: storageService, linkService: ls)
        self._linkService = StateObject(wrappedValue: ls)
    }

    private func togglePin(vm: NoteDetailViewModel) -> () -> Void {
        { var n = vm.note; n.isPinned.toggle(); _ = storageService.saveNote(n); vm.note = n }
    }

    private func toggleStar(vm: NoteDetailViewModel) -> () -> Void {
        { var n = vm.note; n.isStarred.toggle(); _ = storageService.saveNote(n); vm.note = n }
    }

    private func deleteNote(vm: NoteDetailViewModel) {
        _ = storageService.deleteNote(id: vm.note.id)
        windowVM.selectedNoteID = nil
    }
}

// MARK: - RenderedMarkdownView

/// Read-only Markdown rendered as NSAttributedString inside a non-editable NSTextView.
struct RenderedMarkdownView: NSViewRepresentable {

    let body: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let tv = scrollView.documentView as? NSTextView else { return scrollView }
        tv.isEditable           = false
        tv.isSelectable         = true
        tv.drawsBackground      = false
        tv.backgroundColor      = .clear
        tv.textContainerInset   = NSSize(width: 0, height: 0)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        let rendered = MarkdownParser.render(body)
        tv.textStorage?.setAttributedString(rendered)
    }
}

// MARK: - AttachmentTile

/// Small thumbnail tile shown in the attachment strip above the note body.
struct AttachmentTile: View {
    let attachment: Attachment
    @State private var image: NSImage?
    @State private var isExpanded = false

    var body: some View {
        Button(action: { isExpanded = true }) {
            Group {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(NSColor.secondarySystemFill)
                        .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
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
        .onAppear { loadThumbnail() }
        .sheet(isPresented: $isExpanded) {
            expandedSheet
        }
    }

    private func loadThumbnail() {
        DispatchQueue.global(qos: .utility).async {
            let loaded = NSImage(contentsOf: attachment.thumbnailURL)
                ?? NSImage(contentsOf: attachment.absoluteFileURL)
            DispatchQueue.main.async { image = loaded }
        }
    }

    private var expandedSheet: some View {
        VStack {
            if let img = NSImage(contentsOf: attachment.absoluteFileURL) {
                AnnotatedScreenshotView(
                    image: img,
                    annotations: .constant(attachment.annotations),
                    activeTool: .constant(.arrow),
                    activeColor: .constant(.systemRed),
                    strokeWidth: .constant(2.5)
                )
                .frame(minWidth: 600, minHeight: 450)
            }
            Button("Close") { isExpanded = false }
                .padding()
        }
        .frame(minWidth: 640, minHeight: 500)
    }
}
#endif
