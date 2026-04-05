#if os(macOS)
import SwiftUI
import AppKit

// MARK: - ScreenshotPreview

/// Displays a captured screenshot inline in the capture panel.
/// Week 2: image-only display with a remove button.
/// Week 3: will be upgraded with the full annotation canvas overlay.
struct ScreenshotPreview: View {

    let image: NSImage
    /// Called when the user taps the ✕ remove button.
    var onRemove: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Screenshot image — scales proportionally, capped at 240px height
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 240)
                .background(Color(NSColor.underPageBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                )

            // Remove button
            Button(action: { onRemove?() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}

// MARK: - ScreenshotThumbnail

/// Compact thumbnail used in the timeline note rows.
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
                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
            }
        }
        .frame(width: 48, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onAppear { loadImage() }
    }

    private func loadImage() {
        guard image == nil else { return }
        DispatchQueue.global(qos: .utility).async {
            // Prefer the -thumb variant if it exists
            let thumbURL = url
                .deletingPathExtension()
                .appendingPathExtension("thumb")
                .appendingPathExtension(url.pathExtension)
            let loaded = NSImage(contentsOf: thumbURL) ?? NSImage(contentsOf: url)
            DispatchQueue.main.async { image = loaded }
        }
    }
}

// MARK: - Preview (Xcode canvas)

#Preview {
    ScreenshotPreview(image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!)
        .frame(width: 480)
        .padding()
}
#endif
