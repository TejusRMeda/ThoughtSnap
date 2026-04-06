#if os(macOS)
import SwiftUI
import AppKit

// MARK: - AnnotatedScreenshotView

/// Full annotation canvas: wraps `AnnotationCanvasView` as an NSViewRepresentable.
/// Displays the screenshot, all committed annotations, and a live in-progress annotation
/// while the user drags.
///
/// The toolbar (`AnnotationToolbar`) is rendered above this view by `AnnotationEditor`.
struct AnnotatedScreenshotView: NSViewRepresentable {

    let image: NSImage
    @Binding var annotations: [Annotation]
    @Binding var activeTool: Annotation.AnnotationType
    @Binding var activeColor: NSColor
    @Binding var strokeWidth: CGFloat

    /// True while waiting for a text label input sheet before committing a text annotation.
    var pendingTextAnnotation: ((Annotation) -> Void)?

    func makeNSView(context: Context) -> AnnotationCanvasView {
        let canvas = AnnotationCanvasView()
        canvas.image = image
        canvas.annotations = annotations
        canvas.activeTool  = activeTool
        canvas.activeColor = activeColor
        canvas.strokeWidth = strokeWidth

        canvas.onAnnotationAdded = { [weak canvas] ann in
            context.coordinator.handleNewAnnotation(ann, canvas: canvas)
        }
        return canvas
    }

    func updateNSView(_ canvas: AnnotationCanvasView, context: Context) {
        if canvas.image !== image { canvas.image = image }
        canvas.annotations = annotations
        canvas.activeTool  = activeTool
        canvas.activeColor = activeColor
        canvas.strokeWidth = strokeWidth
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    final class Coordinator {
        var parent: AnnotatedScreenshotView

        init(_ parent: AnnotatedScreenshotView) {
            self.parent = parent
        }

        func handleNewAnnotation(_ ann: Annotation, canvas: AnnotationCanvasView?) {
            DispatchQueue.main.async {
                if ann.type == .text {
                    // Defer to text-label sheet — caller handles the popover
                    self.parent.pendingTextAnnotation?(ann)
                } else {
                    self.parent.annotations.append(ann)
                }
            }
        }
    }
}

// MARK: - AnnotationEditor

/// Composite view = AnnotationToolbar + AnnotatedScreenshotView + optional text label sheet.
/// This is the full annotation UX embedded inside the capture panel.
struct AnnotationEditor: View {

    let image: NSImage
    @Binding var annotations: [Annotation]

    var onDone: () -> Void

    @State private var activeTool:   Annotation.AnnotationType = .arrow
    @State private var activeColor:  NSColor = NSColor(hex: "#FF3B30") ?? .systemRed
    @State private var strokeWidth:  CGFloat = 2.5

    // Text label input state
    @State private var showTextSheet     = false
    @State private var pendingAnnotation: Annotation? = nil
    @State private var textLabelInput   = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            AnnotationToolbar(
                selectedTool:  $activeTool,
                selectedColor: $activeColor,
                strokeWidth:   $strokeWidth,
                canUndo: !annotations.isEmpty,
                onUndo: { if !annotations.isEmpty { annotations.removeLast() } },
                onDone: onDone
            )

            Divider()

            // Canvas
            AnnotatedScreenshotView(
                image:        image,
                annotations:  $annotations,
                activeTool:   $activeTool,
                activeColor:  $activeColor,
                strokeWidth:  $strokeWidth,
                pendingTextAnnotation: { ann in
                    pendingAnnotation = ann
                    textLabelInput    = ""
                    showTextSheet     = true
                }
            )
            .frame(maxWidth: .infinity, maxHeight: 260)
            .background(Color(NSColor.underPageBackgroundColor))
        }
        .sheet(isPresented: $showTextSheet) {
            TextLabelInputSheet(
                label: $textLabelInput,
                onCommit: { label in
                    if var ann = pendingAnnotation {
                        ann = Annotation(
                            id: ann.id,
                            type: .text,
                            x: ann.x, y: ann.y,
                            width: ann.width, height: ann.height,
                            colorHex: ann.colorHex,
                            label: label,
                            strokeWidth: ann.strokeWidth
                        )
                        annotations.append(ann)
                    }
                    pendingAnnotation = nil
                    showTextSheet = false
                },
                onCancel: {
                    pendingAnnotation = nil
                    showTextSheet     = false
                }
            )
        }
    }
}

// MARK: - ScreenshotPreview (thumbnail — used in timeline rows)

/// Compact read-only thumbnail with no annotation editing.
struct ScreenshotPreview: View {

    let image: NSImage
    var onRemove: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 200)
                .background(Color(NSColor.underPageBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                )

            if onRemove != nil {
                Button(action: { onRemove?() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
    }
}

// MARK: - ScreenshotThumbnail (async loader for timeline rows)

struct ScreenshotThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(NSColor.secondarySystemFill)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    )
            }
        }
        .frame(width: 48, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onAppear { loadImage() }
    }

    private func loadImage() {
        guard image == nil else { return }
        DispatchQueue.global(qos: .utility).async {
            let thumbURL = url
                .deletingPathExtension()
                .appendingPathExtension("thumb")
                .appendingPathExtension(url.pathExtension)
            let loaded = NSImage(contentsOf: thumbURL) ?? NSImage(contentsOf: url)
            DispatchQueue.main.async { self.image = loaded }
        }
    }
}
#endif
