#if os(macOS)
import SwiftUI
import AppKit
import Combine

// MARK: - CapturePanelWindow

/// NSPanel subclass that:
///   - can become key (required for text input)
///   - appears above fullscreen apps via .fullScreenAuxiliary
///   - never becomes the main window (so it doesn't steal focus from the active app)
final class CapturePanelWindow: NSPanel {

    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [
                .nonactivatingPanel,
                .titled,
                .fullSizeContentView,
                .closable,
            ],
            backing: .buffered,
            defer: false
        )

        // Critical: appear on every Space AND above fullscreen apps
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Sit above regular floating windows
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)

        // Panel aesthetics
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = NSColor.windowBackgroundColor
        hasShadow = true
        isReleasedWhenClosed = false

        if let contentView = contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 12
            contentView.layer?.masksToBounds = true
        }
    }

    func showCentred() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.midX - frame.width  / 2,
            y: screenFrame.midY - frame.height / 2 + 60
        )
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
    }
}

// MARK: - CapturePanelController

/// Owns the CapturePanelWindow and bridges AppKit ↔ SwiftUI.
/// Also injects ScreenCaptureService and wires clipboard monitoring.
final class CapturePanelController {

    private let panel: CapturePanelWindow
    private var hostingView: NSHostingView<CapturePanelContentView>?
    private let storageService: StorageService
    let captureService: ScreenCaptureService
    private var cancellables = Set<AnyCancellable>()

    init(storageService: StorageService) {
        self.storageService   = storageService
        self.captureService   = ScreenCaptureService(storageService: storageService)
        self.panel            = CapturePanelWindow()
        setupContent()
    }

    private func setupContent() {
        let contentView = CapturePanelContentView(
            captureService: captureService,
            onDismiss: { [weak self] in self?.hide() }
        )
        .environmentObject(storageService)

        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 480, height: 360)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hosting)
        hostingView = hosting
    }

    func show() {
        let t0 = CACurrentMediaTime()

        // Start clipboard monitoring when the panel is visible
        captureService.startClipboardMonitoring()

        panel.showCentred()

        let elapsed = (CACurrentMediaTime() - t0) * 1000
        if elapsed > 500 {
            print("[CapturePanelController] ⚠️ SLA VIOLATION: show took \(Int(elapsed))ms (budget: 500ms)")
        }
    }

    func hide() {
        captureService.stopClipboardMonitoring()
        panel.orderOut(nil)
    }
}

// MARK: - CapturePanelViewModel

/// Holds the mutable state for an in-progress capture.
final class CapturePanelViewModel: ObservableObject {
    @Published var bodyText: String = ""
    @Published var attachedImages: [NSImage] = []
    @Published var isSaving: Bool = false
    @Published var isCapturingRegion: Bool = false

    func reset() {
        bodyText = ""
        attachedImages = []
        isSaving = false
        isCapturingRegion = false
    }
}

// MARK: - CapturePanelContentView

struct CapturePanelContentView: View {

    @EnvironmentObject var storageService: StorageService
    @StateObject private var viewModel = CapturePanelViewModel()

    let captureService: ScreenCaptureService
    var onDismiss: () -> Void

    @FocusState private var isTextFocused: Bool
    @State private var clipboardCancellable: AnyCancellable?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            screenshotStrip
            textArea
            Divider()
            footer
        }
        .onAppear {
            viewModel.reset()
            isTextFocused = true
            // Subscribe to clipboard images while panel is visible
            clipboardCancellable = captureService.clipboardImageDetected
                .receive(on: DispatchQueue.main)
                .sink { [weak viewModel] image in
                    viewModel?.attachedImages.append(image)
                }
        }
        .onDisappear {
            clipboardCancellable = nil
        }
    }

    // MARK: - Subviews

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Screenshot region-select button
            Button(action: captureRegion) {
                Label("Screenshot", systemImage: "camera.viewfinder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        PermissionsHelper.hasScreenRecordingPermission()
                            ? Color.primary
                            : Color.secondary
                    )
            }
            .buttonStyle(.plain)
            .help(
                PermissionsHelper.hasScreenRecordingPermission()
                    ? "Capture a screen region (⌘⇧S)"
                    : "Screen Recording permission required"
            )
            .disabled(!PermissionsHelper.hasScreenRecordingPermission())
            .keyboardShortcut("s", modifiers: [.command, .shift])

            // Clipboard paste button
            Button(action: pasteClipboard) {
                Label("Paste", systemImage: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Paste image from clipboard (⌘V)")
            .keyboardShortcut("v", modifiers: .command)

            Spacer()

            Text("ThoughtSnap")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// Horizontal scroll strip of attached screenshot previews.
    @ViewBuilder
    private var screenshotStrip: some View {
        if !viewModel.attachedImages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.attachedImages.enumerated()), id: \.offset) { idx, img in
                        ScreenshotPreview(image: img) {
                            viewModel.attachedImages.remove(at: idx)
                        }
                        // Week 3: ScreenshotPreview will be replaced by the annotation canvas
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 260)

            Divider()
        }
    }

    private var textArea: some View {
        TextEditor(text: $viewModel.bodyText)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .background(.clear)
            .focused($isTextFocused)
            .frame(minHeight: 100, maxHeight: 200)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(alignment: .topLeading) {
                if viewModel.bodyText.isEmpty {
                    Text("Type a thought… #tag  [[link]]")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            // Hint text
            Text(viewModel.attachedImages.isEmpty ? "#tag  [[link]]" : "\(viewModel.attachedImages.count) screenshot(s)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer()

            Button(action: dismiss) {
                Text("Cancel")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .keyboardShortcut(.escape, modifiers: [])
            .buttonStyle(.plain)

            Button(action: save) {
                HStack(spacing: 4) {
                    if viewModel.isSaving {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("Save")
                            .font(.system(size: 13, weight: .medium))
                        Text("⌘↩")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.7))
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

    // MARK: - Computed

    private var canSave: Bool {
        !viewModel.isSaving && (
            !viewModel.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.attachedImages.isEmpty
        )
    }

    // MARK: - Actions

    private func captureRegion() {
        // Minimise panel, show overlay; restore panel after capture
        viewModel.isCapturingRegion = true
        captureService.captureRegion { [weak viewModel] image in
            DispatchQueue.main.async {
                viewModel?.isCapturingRegion = false
                if let img = image {
                    viewModel?.attachedImages.append(img)
                }
            }
        }
    }

    private func pasteClipboard() {
        let pb = NSPasteboard.general
        guard let images = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage],
              let image = images.first
        else { return }
        viewModel.attachedImages.append(image)
    }

    private func save() {
        let trimmed = viewModel.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !viewModel.attachedImages.isEmpty else { return }

        viewModel.isSaving = true

        var note = Note.empty()
        note.body = trimmed
        note.tags = Note.extractTags(from: trimmed)
        note.spaceIDs = [Space.inbox.id]

        // Persist the note first
        let t0 = CACurrentMediaTime()
        let saveResult = storageService.saveNote(note)

        let elapsed = (CACurrentMediaTime() - t0) * 1000
        if elapsed > 200 {
            print("[CapturePanelContentView] ⚠️ SLA VIOLATION: note save took \(Int(elapsed))ms (budget: 200ms)")
        }

        guard case .success = saveResult else {
            viewModel.isSaving = false
            return
        }

        // Persist attachments on a background queue (non-blocking)
        let images = viewModel.attachedImages
        let noteID = note.id
        if !images.isEmpty {
            DispatchQueue.global(qos: .userInitiated).async { [weak storageService] in
                guard let ss = storageService else { return }
                for image in images {
                    if let attachment = try? ScreenCaptureService(storageService: ss)
                        .saveScreenshot(image) {
                        _ = ss.saveAttachment(attachment, for: noteID)
                    }
                }
            }
        }

        viewModel.isSaving = false
        dismiss()
    }

    private func dismiss() {
        viewModel.reset()
        isTextFocused = false
        onDismiss()
    }
}
#endif
