#if os(macOS)
import SwiftUI
import AppKit
import Combine

// MARK: - CapturePanelWindow

/// NSPanel subclass:
///   - can become key (required for text input)
///   - appears above fullscreen apps via .fullScreenAuxiliary
///   - never becomes main window
final class CapturePanelWindow: NSPanel {

    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        isMovableByWindowBackground = true
        hidesOnDeactivate  = false
        titleVisibility    = .hidden
        titlebarAppearsTransparent = true
        backgroundColor    = NSColor.windowBackgroundColor
        hasShadow          = true
        isReleasedWhenClosed = false
        if let cv = contentView {
            cv.wantsLayer = true
            cv.layer?.cornerRadius  = 12
            cv.layer?.masksToBounds = true
        }
    }

    func showCentred() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let f = screen.visibleFrame
        setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.midY - frame.height / 2 + 60))
        makeKeyAndOrderFront(nil)
    }
}

// MARK: - CapturePanelController

final class CapturePanelController {

    private let panel: CapturePanelWindow
    private let storageService: StorageService
    let captureService: ScreenCaptureService
    private var cancellables = Set<AnyCancellable>()

    init(storageService: StorageService) {
        self.storageService = storageService
        self.captureService = ScreenCaptureService(storageService: storageService)
        self.panel = CapturePanelWindow()
        setupContent()
    }

    private func setupContent() {
        let view = CapturePanelContentView(
            captureService: captureService,
            onDismiss: { [weak self] in self?.hide() }
        )
        .environmentObject(storageService)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hosting)
    }

    func show() {
        let t0 = CACurrentMediaTime()
        captureService.startClipboardMonitoring()
        panel.showCentred()
        let ms = (CACurrentMediaTime() - t0) * 1000
        if ms > 500 { print("[CapturePanelController] ⚠️ SLA: show \(Int(ms))ms > 500ms") }
    }

    func hide() {
        captureService.stopClipboardMonitoring()
        panel.orderOut(nil)
    }
}

// MARK: - AttachedCapture

/// One screenshot + its annotation layer, held in the view model.
struct AttachedCapture: Identifiable {
    let id = UUID()
    var image: NSImage
    var annotations: [Annotation] = []
}

// MARK: - CapturePanelViewModel

final class CapturePanelViewModel: ObservableObject {
    @Published var bodyText: String = ""
    @Published var captures: [AttachedCapture] = []
    @Published var isSaving: Bool = false
    @Published var editingCaptureIndex: Int? = nil   // index of capture currently being annotated

    func reset() {
        bodyText = ""; captures = []; isSaving = false; editingCaptureIndex = nil
    }
}

// MARK: - CapturePanelContentView

struct CapturePanelContentView: View {

    @EnvironmentObject var storageService: StorageService
    @StateObject private var vm = CapturePanelViewModel()

    let captureService: ScreenCaptureService
    var onDismiss: () -> Void

    @FocusState private var textFocused: Bool
    @State private var clipboardSub: AnyCancellable?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            captureArea
            textArea
            Divider()
            footer
        }
        .onAppear {
            vm.reset()
            textFocused = true
            clipboardSub = captureService.clipboardImageDetected
                .receive(on: DispatchQueue.main)
                .sink { [weak vm] img in vm?.captures.append(AttachedCapture(image: img)) }
        }
        .onDisappear { clipboardSub = nil }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: captureRegion) {
                Label("Screenshot", systemImage: "camera.viewfinder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        PermissionsHelper.hasScreenRecordingPermission() ? Color.primary : .secondary
                    )
            }
            .buttonStyle(.plain)
            .disabled(!PermissionsHelper.hasScreenRecordingPermission())
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .help(PermissionsHelper.hasScreenRecordingPermission()
                  ? "Capture region (⌘⇧S)" : "Screen Recording permission required")

            Button(action: pasteClipboard) {
                Label("Paste", systemImage: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("v", modifiers: .command)
            .help("Paste image (⌘V)")

            Spacer()
            Text("ThoughtSnap")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()

            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: Capture area (screenshots + annotation editors)

    @ViewBuilder
    private var captureArea: some View {
        if !vm.captures.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(vm.captures.indices, id: \.self) { idx in
                        captureCard(idx: idx)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: vm.editingCaptureIndex != nil ? 340 : 220)

            Divider()
        }
    }

    @ViewBuilder
    private func captureCard(idx: Int) -> some View {
        let isEditing = vm.editingCaptureIndex == idx

        VStack(spacing: 0) {
            if isEditing {
                // Full annotation editor for the active card
                AnnotationEditor(
                    image: vm.captures[idx].image,
                    annotations: Binding(
                        get: { vm.captures[idx].annotations },
                        set: { vm.captures[idx].annotations = $0 }
                    ),
                    onDone: { vm.editingCaptureIndex = nil }
                )
                .frame(width: 440)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                )
            } else {
                // Thumbnail with an Edit button overlay
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: vm.captures[idx].image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )

                    // Annotation count badge
                    let annCount = vm.captures[idx].annotations.count
                    if annCount > 0 {
                        Text("\(annCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                            .offset(x: -4, y: -4)
                    }

                    // Edit button
                    Button(action: { vm.editingCaptureIndex = idx }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: 6)
                }
                .overlay(alignment: .topTrailing) {
                    // Remove button
                    Button(action: { removeCapture(at: idx) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            }
        }
    }

    // MARK: Text area

    private var textArea: some View {
        TextEditor(text: $vm.bodyText)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .background(.clear)
            .focused($textFocused)
            .frame(minHeight: vm.captures.isEmpty ? 130 : 70, maxHeight: 180)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(alignment: .topLeading) {
                if vm.bodyText.isEmpty {
                    Text("Type a thought… #tag  [[link]]")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(vm.captures.isEmpty ? "#tag  [[link]]" : "\(vm.captures.count) screenshot(s)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()

            Button("Cancel", action: dismiss)
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            Button(action: save) {
                HStack(spacing: 4) {
                    if vm.isSaving {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("Save").font(.system(size: 13, weight: .medium))
                        Text("⌘↩").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(canSave ? Color.accentColor : Color.secondary.opacity(0.3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Helpers

    private var canSave: Bool {
        !vm.isSaving && (
            !vm.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !vm.captures.isEmpty
        )
    }

    private func captureRegion() {
        captureService.captureRegion { img in
            DispatchQueue.main.async {
                if let img { vm.captures.append(AttachedCapture(image: img)) }
            }
        }
    }

    private func pasteClipboard() {
        guard let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage],
              let img = images.first else { return }
        vm.captures.append(AttachedCapture(image: img))
    }

    private func removeCapture(at idx: Int) {
        guard idx < vm.captures.count else { return }
        vm.captures.remove(at: idx)
        if vm.editingCaptureIndex == idx { vm.editingCaptureIndex = nil }
    }

    // MARK: Save

    private func save() {
        let trimmed = vm.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave else { return }

        vm.isSaving = true
        var note = Note.empty()
        note.body     = trimmed
        note.tags     = Note.extractTags(from: trimmed)
        note.spaceIDs = [Space.inbox.id]

        let t0 = CACurrentMediaTime()
        guard case .success = storageService.saveNote(note) else {
            vm.isSaving = false; return
        }
        let ms = (CACurrentMediaTime() - t0) * 1000
        if ms > 200 { print("[CapturePanelContentView] ⚠️ SLA: save \(Int(ms))ms > 200ms") }

        // Persist attachments + annotations on background queue
        let captures = vm.captures
        let noteID   = note.id
        let ss       = storageService
        DispatchQueue.global(qos: .userInitiated).async {
            let captureSvc = ScreenCaptureService(storageService: ss)
            for capture in captures {
                guard let attachment = try? captureSvc.saveScreenshot(capture.image) else { continue }
                _ = ss.saveAttachment(attachment, for: noteID)

                // Persist annotations
                if !capture.annotations.isEmpty {
                    _ = ss.saveAnnotations(capture.annotations, for: attachment.id)
                }

                // OCR (async enrichment — does not block save)
                if let cgImg = capture.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    Task {
                        let ocr = OCRService()
                        if let text = try? await ocr.recognizeText(in: cgImg) {
                            ss.updateOCRText(text, for: attachment.id)
                        }
                    }
                }
            }

            // Update FTS annotation_labels for the note
            let allLabels = captures
                .flatMap { $0.annotations }
                .compactMap { $0.label }
                .joined(separator: " ")
            if !allLabels.isEmpty {
                ss.updateFTSAnnotationLabels(noteID: noteID, labels: allLabels)
            }
        }

        vm.isSaving = false
        dismiss()
    }

    private func dismiss() {
        vm.reset()
        textFocused = false
        onDismiss()
    }
}
#endif
