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
                .nonactivatingPanel,   // doesn't deactivate the current app
                .titled,
                .fullSizeContentView,
                .closable,
            ],
            backing: .buffered,
            defer: false
        )

        // Critical: appear on every Space and above fullscreen apps
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Sit above regular floating windows
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)

        // Panel aesthetics
        isMovableByWindowBackground = true
        hidesOnDeactivate = false        // stay visible when user switches to another app
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = NSColor.windowBackgroundColor
        hasShadow = true
        isReleasedWhenClosed = false     // keep in memory for fast re-show

        // Corner radius via layer
        if let contentView = contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 12
            contentView.layer?.masksToBounds = true
        }
    }

    /// Show the panel centred on the current screen (or near the last mouse position).
    func showCentred() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.midX - frame.width / 2,
            y: screenFrame.midY - frame.height / 2 + 60  // slightly above centre
        )
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
    }
}

// MARK: - CapturePanelController

/// Owns the CapturePanelWindow and bridges between AppKit and the SwiftUI content view.
final class CapturePanelController {

    private let panel: CapturePanelWindow
    private var hostingView: NSHostingView<CapturePanelContentView>?
    private let storageService: StorageService

    init(storageService: StorageService) {
        self.storageService = storageService
        self.panel = CapturePanelWindow()
        setupContent()
    }

    private func setupContent() {
        let contentView = CapturePanelContentView(onDismiss: { [weak self] in
            self?.hide()
        })
        .environmentObject(storageService)

        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 480, height: 360)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hosting)
        hostingView = hosting
    }

    func show() {
        // Measure time to panel visible (SLA: <500ms)
        let t0 = CACurrentMediaTime()
        panel.showCentred()
        let elapsed = (CACurrentMediaTime() - t0) * 1000
        if elapsed > 500 {
            print("[CapturePanelController] ⚠️ SLA VIOLATION: panel show took \(Int(elapsed))ms (budget: 500ms)")
        }
    }

    func hide() {
        panel.orderOut(nil)
    }
}

// MARK: - CapturePanelContentView

/// The SwiftUI content rendered inside the floating panel.
struct CapturePanelContentView: View {

    @EnvironmentObject var storageService: StorageService

    var onDismiss: () -> Void

    @State private var bodyText: String = ""
    @State private var isSaving: Bool = false
    @FocusState private var isTextFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar row
            HStack(spacing: 8) {
                Text("ThoughtSnap")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            // Text editor
            TextEditor(text: $bodyText)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .background(.clear)
                .focused($isTextFocused)
                .frame(minHeight: 120)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            Divider()

            // Footer row
            HStack {
                // Tag / link hints
                Text("#tag  [[link]]")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(action: dismiss) {
                    Text("Cancel")
                        .font(.system(size: 13))
                }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(action: save) {
                    HStack(spacing: 4) {
                        Text("Save")
                            .font(.system(size: 13, weight: .medium))
                        Text("⌘↩")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.plain)
                .disabled(isSaving || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear {
            bodyText = ""
            isTextFocused = true
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true

        // Build the note — tags and links extracted from body
        var note = Note.empty()
        note.body = trimmed
        note.tags = Note.extractTags(from: trimmed)
        note.spaceIDs = [Space.inbox.id]

        let t0 = CACurrentMediaTime()
        let result = storageService.saveNote(note)
        let elapsed = (CACurrentMediaTime() - t0) * 1000

        if elapsed > 200 {
            print("[CapturePanelContentView] ⚠️ SLA VIOLATION: save took \(Int(elapsed))ms (budget: 200ms)")
        }

        switch result {
        case .success:
            isSaving = false
            dismiss()
        case .failure(let error):
            print("[CapturePanelContentView] Save failed: \(error)")
            isSaving = false
        }
    }

    private func dismiss() {
        bodyText = ""
        onDismiss()
    }
}
#endif
