#if os(macOS)
import AppKit

// MARK: - ScreenSelectionOverlayWindow

/// A borderless, fullscreen NSWindow that covers all displays and lets the user
/// drag a selection rectangle to define the screenshot region.
///
/// Window level is `.screenSaver + 1` so it appears above all app windows,
/// including fullscreen apps. Dismissed on mouse-up or Escape key.
final class ScreenSelectionOverlayWindow: NSWindow {

    private var overlayView: SelectionOverlayView?
    /// Called with the selected CGRect in screen coordinates, or nil on cancel.
    private var completion: ((CGRect?) -> Void)?

    init(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion

        // Cover the entire main display (extend to all screens if multi-monitor needed)
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level            = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        backgroundColor  = NSColor.black.withAlphaComponent(0.35)
        isOpaque         = false
        hasShadow        = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let view = SelectionOverlayView(frame: screenFrame)
        view.onSelection = { [weak self] rect in
            self?.finish(rect: rect)
        }
        view.onCancel = { [weak self] in
            self?.finish(rect: nil)
        }
        contentView = view
        overlayView = view
    }

    func show() {
        makeKeyAndOrderFront(nil)
        // Change cursor to crosshair
        NSCursor.crosshair.push()
    }

    private func finish(rect: CGRect?) {
        NSCursor.pop()
        orderOut(nil)
        completion?(rect)
        completion = nil
    }
}

// MARK: - SelectionOverlayView

/// Custom NSView that handles mouse dragging to define a selection rectangle,
/// and draws a crosshair + live selection box with a semi-transparent fill.
private final class SelectionOverlayView: NSView {

    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect?

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Background — drawn by the window's backgroundColor; we add a subtle vignette
        NSColor.black.withAlphaComponent(0.25).setFill()
        dirtyRect.fill()

        guard let selection = currentRect else { return }

        // Punch through the overlay inside the selection (clear fill)
        NSGraphicsContext.saveGraphicsState()
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: selection).reversed)
        NSColor.black.withAlphaComponent(0.35).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Clear the selected region itself
        NSColor.clear.setFill()
        selection.fill()

        // Border
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 1.5
        border.stroke()

        // Corner handles
        drawCornerHandles(in: selection)

        // Dimensions label
        drawDimensionsLabel(for: selection)
    }

    private func drawCornerHandles(in rect: NSRect) {
        let size: CGFloat = 6
        NSColor.white.setFill()
        let corners: [NSPoint] = [
            rect.origin,
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
        ]
        for corner in corners {
            NSBezierPath(ovalIn: NSRect(
                x: corner.x - size / 2,
                y: corner.y - size / 2,
                width: size,
                height: size
            )).fill()
        }
    }

    private func drawDimensionsLabel(for rect: NSRect) {
        let w = Int(rect.width)
        let h = Int(rect.height)
        let label = "\(w) × \(h)"

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 6
        let bg = NSRect(
            x: rect.midX - size.width / 2 - padding,
            y: rect.maxY + 6,
            width: size.width + padding * 2,
            height: size.height + padding
        )
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        (label as NSString).draw(
            at: NSPoint(x: bg.origin.x + padding, y: bg.origin.y + padding / 2),
            withAttributes: attributes
        )
    }

    // MARK: - Mouse tracking

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width:  abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = currentRect, rect.width > 4, rect.height > 4 else {
            onCancel?()
            return
        }
        // Convert from AppKit view coordinates (origin bottom-left) to
        // screen coordinates expected by ScreenCaptureService
        let screenRect = convertToScreen(rect)
        onSelection?(screenRect)
    }

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Escape
            onCancel?()
        }
    }

    // MARK: - Coordinate conversion

    /// Converts this view's local NSRect into screen coordinates.
    /// AppKit view origin is bottom-left; screen coordinates are also bottom-left on macOS.
    private func convertToScreen(_ rect: NSRect) -> CGRect {
        guard let window = self.window else { return rect }
        let windowRect = convert(rect, to: nil)          // view → window
        let screenRect = window.convertToScreen(windowRect) // window → screen
        return screenRect
    }

    // MARK: - Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        return self  // capture all mouse events
    }
}
#endif
