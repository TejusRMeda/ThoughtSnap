#if os(macOS)
import AppKit
import CoreGraphics
import Combine

// MARK: - ScreenCaptureService

/// Handles all screenshot capture modes:
///   1. Full-screen snapshot (background, for quick attach)
///   2. Region selection overlay (interactive crosshair + drag)
///   3. Clipboard image paste detection (0.5s polling)
///
/// All captured images are saved as PNG to:
///   ~/Library/Application Support/ThoughtSnap/attachments/YYYY-MM/{uuid}.png
/// Thumbnails (600px wide) are generated on a background queue alongside each save.
final class ScreenCaptureService: ObservableObject {

    // MARK: - Publishers

    /// Fires when a clipboard image is detected (paste flow).
    let clipboardImageDetected = PassthroughSubject<NSImage, Never>()

    // MARK: - Private

    private let storageService: StorageService
    private var clipboardTimer: Timer?
    private var lastClipboardChangeCount: Int = NSPasteboard.general.changeCount
    private var selectionOverlay: ScreenSelectionOverlayWindow?

    // MARK: - Init

    init(storageService: StorageService) {
        self.storageService = storageService
    }

    // MARK: - Clipboard monitoring

    func startClipboardMonitoring() {
        stopClipboardMonitoring()
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stopClipboardMonitoring() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = currentCount

        guard let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage],
              let image = images.first
        else { return }

        DispatchQueue.main.async { [weak self] in
            self?.clipboardImageDetected.send(image)
        }
    }

    // MARK: - Full-screen snapshot

    /// Captures the current display contents as a CGImage.
    /// Does NOT require a permission dialog if Screen Recording is already granted.
    func captureFullScreen() -> CGImage? {
        guard PermissionsHelper.hasScreenRecordingPermission() else { return nil }
        return CGWindowListCreateImage(
            .infinite,
            .optionAll,
            kCGNullWindowID,
            .bestResolution
        )
    }

    // MARK: - Region selection

    /// Shows the interactive region-select overlay, then calls `completion` with
    /// the captured image (or nil if the user cancelled).
    func captureRegion(completion: @escaping (NSImage?) -> Void) {
        guard PermissionsHelper.hasScreenRecordingPermission() else {
            completion(nil)
            return
        }

        selectionOverlay = ScreenSelectionOverlayWindow { [weak self] selectedRect in
            self?.selectionOverlay = nil

            guard let rect = selectedRect else {
                completion(nil)
                return
            }

            let t0 = CACurrentMediaTime()
            let image = self?.captureRect(rect)
            let elapsed = (CACurrentMediaTime() - t0) * 1000
            if elapsed > 300 {
                print("[ScreenCaptureService] ⚠️ SLA: region capture took \(Int(elapsed))ms (budget: 300ms)")
            }
            completion(image)
        }
        selectionOverlay?.show()
    }

    // MARK: - Rect capture

    private func captureRect(_ rect: CGRect) -> NSImage? {
        // CGWindowListCreateImage uses screen coordinates (origin bottom-left on macOS).
        // The rect from the overlay is in AppKit flipped coordinates; convert it.
        let screenRect = convertToScreenCoordinates(rect)

        guard let cgImage = CGWindowListCreateImage(
            screenRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Converts AppKit window-relative rect to CGWindowListCreateImage screen rect.
    /// CGWindowListCreateImage expects coordinates with origin at top-left on screen.
    private func convertToScreenCoordinates(_ rect: CGRect) -> CGRect {
        guard let screen = NSScreen.main else { return rect }
        let screenHeight = screen.frame.height
        // Flip Y for CoreGraphics (CG has origin bottom-left, AppKit has origin top-left for this overlay)
        return CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: - Save to disk

    /// Saves an NSImage to the dated attachments directory, generates a thumbnail,
    /// and returns a new `Attachment` value (not yet persisted to SQLite).
    func saveScreenshot(_ image: NSImage, date: Date = Date()) throws -> Attachment {
        let dir = storageService.attachmentDirectory(for: date)
        let attachmentID = UUID()
        let filename = "\(attachmentID.uuidString).png"
        let fileURL = dir.appendingPathComponent(filename)

        // Write full-res PNG
        try writePNG(image, to: fileURL)

        // Generate thumbnail asynchronously (doesn't block the SLA)
        let thumbURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("thumb")
            .appendingPathExtension("png")
        DispatchQueue.global(qos: .utility).async {
            try? self.writeThumbnail(of: image, to: thumbURL, maxWidth: 600)
        }

        // Build relative path for storage
        let base = StorageService.appSupportDirectory.path
        let relativePath = fileURL.path.hasPrefix(base)
            ? String(fileURL.path.dropFirst(base.count + 1))
            : fileURL.path

        return Attachment(
            id: attachmentID,
            type: .screenshot,
            filePath: relativePath,
            annotations: [],
            ocrText: nil,
            createdAt: date
        )
    }

    // MARK: - PNG writing helpers

    private func writePNG(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw ScreenCaptureError.conversionFailed
        }
        try png.write(to: url, options: .atomic)
    }

    private func writeThumbnail(of image: NSImage, to url: URL, maxWidth: CGFloat) throws {
        let originalSize = image.size
        guard originalSize.width > 0 else { return }

        let scale = min(1.0, maxWidth / originalSize.width)
        let thumbSize = CGSize(
            width: originalSize.width  * scale,
            height: originalSize.height * scale
        )

        let thumb = NSImage(size: thumbSize)
        thumb.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: thumbSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .sourceOver,
            fraction: 1.0
        )
        thumb.unlockFocus()

        try writePNG(thumb, to: url)
    }
}

// MARK: - ScreenCaptureError

enum ScreenCaptureError: Error, LocalizedError {
    case permissionDenied
    case conversionFailed
    case noImageData

    var errorDescription: String? {
        switch self {
        case .permissionDenied:  return "Screen Recording permission is required."
        case .conversionFailed:  return "Failed to convert image to PNG."
        case .noImageData:       return "No image data available."
        }
    }
}
#endif
