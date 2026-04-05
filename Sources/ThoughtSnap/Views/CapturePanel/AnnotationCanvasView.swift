#if os(macOS)
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - AnnotationCanvasView

/// Custom NSView that renders a base screenshot image with a stack of `Annotation` objects
/// drawn on top via Core Graphics.
///
/// Responsibilities:
///   - Draw the base CGImage scaled to fit the view bounds
///   - Draw all committed annotations
///   - Track mouse drag to show a live in-progress annotation
///   - Append the completed annotation to `annotations` on mouseUp
///   - Cache CIImage blurs so redraws are cheap
///
/// This view is wrapped by `AnnotatedScreenshotView` (NSViewRepresentable).
final class AnnotationCanvasView: NSView {

    // MARK: - Public state (set by owner)

    /// The base screenshot. Setting this triggers a redraw.
    var image: NSImage? { didSet { invalidateBlurCache(); setNeedsDisplay(bounds) } }

    /// Committed annotations. Setting this triggers a redraw.
    var annotations: [Annotation] = [] { didSet { invalidateBlurCache(); setNeedsDisplay(bounds) } }

    /// Currently active drawing tool.
    var activeTool: Annotation.AnnotationType = .arrow

    /// Colour for newly created annotations.
    var activeColor: NSColor = NSColor(hex: "#FF3B30") ?? .systemRed

    /// Stroke width for arrows and rects.
    var strokeWidth: CGFloat = 2.5

    /// Called whenever a new annotation is completed (mouseUp).
    var onAnnotationAdded: ((Annotation) -> Void)?

    // MARK: - Private drawing state

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var isDrawing = false

    // MARK: - Blur cache

    /// Maps annotation ID → pre-rendered blurred CGImage for the blur region.
    private var blurCache: [UUID: CGImage] = [:]

    private func invalidateBlurCache() {
        blurCache.removeAll()
    }

    // MARK: - Image coordinate helpers

    /// The rect inside the view bounds where the image is drawn (aspect-fit).
    private var imageDrawRect: CGRect {
        guard let image else { return bounds }
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imgSize.width, bounds.height / imgSize.height)
        let drawW = imgSize.width  * scale
        let drawH = imgSize.height * scale
        return CGRect(
            x: (bounds.width  - drawW) / 2,
            y: (bounds.height - drawH) / 2,
            width: drawW,
            height: drawH
        )
    }

    /// Converts a point in view-local coordinates to image-normalised (0–1) coordinates.
    private func viewToNormalised(_ pt: NSPoint) -> NSPoint {
        let r = imageDrawRect
        guard r.width > 0, r.height > 0 else { return pt }
        return NSPoint(x: (pt.x - r.minX) / r.width, y: (pt.y - r.minY) / r.height)
    }

    /// Converts normalised coordinates back to view-local coordinates.
    private func normalisedToView(_ pt: NSPoint) -> NSPoint {
        let r = imageDrawRect
        return NSPoint(x: r.minX + pt.x * r.width, y: r.minY + pt.y * r.height)
    }

    /// Converts a stored Annotation (normalised frame) to a CGRect in view coordinates.
    private func annotationViewRect(_ ann: Annotation) -> CGRect {
        let r = imageDrawRect
        return CGRect(
            x: r.minX + ann.x * r.width,
            y: r.minY + ann.y * r.height,
            width:  ann.width  * r.width,
            height: ann.height * r.height
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw base image
        if let img = image, let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let drawRect = imageDrawRect
            ctx.draw(cgImg, in: drawRect)
        }

        // 2. Draw committed annotations
        for ann in annotations {
            let rect = annotationViewRect(ann)
            draw(annotation: ann, in: rect, ctx: ctx)
        }

        // 3. Draw in-progress annotation (live preview during drag)
        if isDrawing, let start = startPoint, let current = currentPoint {
            let liveRect = rectFrom(start, to: current)
            let liveAnn = Annotation(
                type: activeTool,
                x: 0, y: 0, width: 0, height: 0,   // frame unused for live draw
                colorHex: activeColor.hexString,
                strokeWidth: Double(strokeWidth)
            )
            draw(annotation: liveAnn, in: liveRect, ctx: ctx, isLive: true)
        }
    }

    // MARK: - Per-annotation rendering

    private func draw(annotation ann: Annotation, in rect: CGRect, ctx: CGContext, isLive: Bool = false) {
        let color = isLive ? activeColor : ann.nsColor

        switch ann.type {
        case .arrow:
            drawArrow(from: CGPoint(x: rect.minX, y: rect.minY),
                      to:   CGPoint(x: rect.maxX, y: rect.maxY),
                      color: color,
                      lineWidth: isLive ? strokeWidth : CGFloat(ann.strokeWidth),
                      ctx: ctx)

        case .rect:
            drawRect(rect, color: color,
                     lineWidth: isLive ? strokeWidth : CGFloat(ann.strokeWidth),
                     ctx: ctx)

        case .text:
            let text = isLive ? "" : (ann.label ?? "")
            drawTextLabel(text, at: CGPoint(x: rect.minX, y: rect.minY), color: color, ctx: ctx)

        case .highlight:
            drawHighlight(rect, color: color, ctx: ctx)

        case .blur:
            drawBlur(ann: ann, rect: rect, ctx: ctx, isLive: isLive)
        }
    }

    // MARK: Arrow

    private func drawArrow(from start: CGPoint, to end: CGPoint,
                           color: NSColor, lineWidth: CGFloat, ctx: CGContext) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx*dx + dy*dy)
        guard length > 4 else { return }

        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)

        // Shaft
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()

        // Arrowhead
        let angle = atan2(dy, dx)
        let headLen: CGFloat = max(10, lineWidth * 4)
        let headAngle: CGFloat = .pi / 6   // 30°

        let p1 = CGPoint(
            x: end.x - headLen * cos(angle - headAngle),
            y: end.y - headLen * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLen * cos(angle + headAngle),
            y: end.y - headLen * sin(angle + headAngle)
        )

        let path = CGMutablePath()
        path.move(to: end)
        path.addLine(to: p1)
        path.addLine(to: p2)
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()

        ctx.restoreGState()
    }

    // MARK: Rectangle

    private func drawRect(_ rect: CGRect, color: NSColor, lineWidth: CGFloat, ctx: CGContext) {
        guard rect.width > 2, rect.height > 2 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.square)
        ctx.stroke(rect)
        ctx.restoreGState()
    }

    // MARK: Text label

    private func drawTextLabel(_ text: String, at origin: CGPoint, color: NSColor, ctx: CGContext) {
        guard !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: color,
        ]
        let nsText = text as NSString
        let size = nsText.size(withAttributes: attributes)
        let padding: CGFloat = 4
        let bg = CGRect(
            x: origin.x - padding,
            y: origin.y - padding,
            width:  size.width  + padding * 2,
            height: size.height + padding * 2
        )

        // Semi-transparent background pill
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        let pill = CGPath(roundedRect: bg, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(pill)
        ctx.fillPath()
        ctx.restoreGState()

        // Draw text via NSGraphicsContext (required for NSString drawing)
        NSGraphicsContext.saveGraphicsState()
        if let nsCtx = NSGraphicsContext.current {
            let _ = nsCtx  // ensure context is active
            nsText.draw(at: CGPoint(x: origin.x, y: origin.y), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Highlight

    private func drawHighlight(_ rect: CGRect, color: NSColor, ctx: CGContext) {
        guard rect.width > 2, rect.height > 2 else { return }
        ctx.saveGState()
        ctx.setFillColor(color.withAlphaComponent(0.4).cgColor)
        ctx.fill(rect)
        ctx.restoreGState()
    }

    // MARK: Blur

    private func drawBlur(ann: Annotation, rect: CGRect, ctx: CGContext, isLive: Bool) {
        guard rect.width > 4, rect.height > 4 else { return }

        // For a live drag preview, just draw a semi-transparent dark rect
        if isLive {
            ctx.saveGState()
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.fill(rect)
            ctx.restoreGState()
            return
        }

        // Use cached blur if available
        if let cachedBlur = blurCache[ann.id] {
            ctx.draw(cachedBlur, in: rect)
            return
        }

        // Extract the sub-image at `rect` from the base image and blur it
        guard let baseImg = image,
              let cgBase = baseImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let drawRect = imageDrawRect
        guard drawRect.width > 0, drawRect.height > 0 else { return }

        // Map rect (view coords) → pixel coords in the full image
        let scaleX = CGFloat(cgBase.width)  / drawRect.width
        let scaleY = CGFloat(cgBase.height) / drawRect.height
        let cropRect = CGRect(
            x: (rect.minX - drawRect.minX) * scaleX,
            y: (rect.minY - drawRect.minY) * scaleY,
            width:  rect.width  * scaleX,
            height: rect.height * scaleY
        )

        guard let subImage = cgBase.cropping(to: cropRect) else { return }

        let ciInput = CIImage(cgImage: subImage)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = ciInput
        filter.radius = 12

        let ciContext = CIContext()
        guard let outputCI = filter.outputImage,
              let blurred = ciContext.createCGImage(outputCI, from: ciInput.extent)
        else { return }

        blurCache[ann.id] = blurred
        ctx.draw(blurred, in: rect)
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        startPoint  = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        isDrawing   = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDrawing, let start = startPoint else { return }
        let end = convert(event.locationInWindow, from: nil)
        isDrawing   = false
        startPoint  = nil
        currentPoint = nil

        let viewRect = rectFrom(start, to: end)

        // Normalise coordinates relative to imageDrawRect
        let r = imageDrawRect
        guard r.width > 0, r.height > 0 else { return }
        let normX = (viewRect.minX - r.minX) / r.width
        let normY = (viewRect.minY - r.minY) / r.height
        let normW =  viewRect.width  / r.width
        let normH =  viewRect.height / r.height

        // Require a minimum gesture size to avoid accidental taps
        let minNorm: Double = 0.01
        guard activeTool == .text || (normW > minNorm && normH > minNorm) else {
            setNeedsDisplay(bounds)
            return
        }

        let ann = Annotation(
            type: activeTool,
            x: Double(normX),
            y: Double(normY),
            width:  Double(normW),
            height: Double(normH),
            colorHex: activeColor.hexString,
            strokeWidth: Double(strokeWidth)
        )
        onAnnotationAdded?(ann)
        setNeedsDisplay(bounds)
    }

    // MARK: - Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Helper

    private func rectFrom(_ a: NSPoint, _ b: NSPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width:  abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}

// MARK: - NSColor hex helper

extension NSColor {
    /// Returns a 6-character hex string like "#FF3B30".
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(rgb.redComponent   * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent  * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
#endif
