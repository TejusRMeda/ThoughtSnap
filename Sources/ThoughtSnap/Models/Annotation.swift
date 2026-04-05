#if os(macOS)
import Foundation
import AppKit

// MARK: - Annotation

struct Annotation: Identifiable, Codable, Equatable {
    let id: UUID
    var type: AnnotationType
    // Frame stored as Doubles to keep Codable simple (CGFloat isn't Codable by default)
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// Hex color string, e.g. "#FF3B30"
    var colorHex: String
    /// Only set for `.text` annotations
    var label: String?
    var strokeWidth: Double

    init(
        id: UUID = UUID(),
        type: AnnotationType,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        colorHex: String = Annotation.defaultColorHex(for: .arrow),
        label: String? = nil,
        strokeWidth: Double = 2.0
    ) {
        self.id = id
        self.type = type
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.colorHex = colorHex
        self.label = label
        self.strokeWidth = strokeWidth
    }
}

// MARK: - AnnotationType

extension Annotation {
    enum AnnotationType: String, Codable, Equatable, CaseIterable {
        case arrow
        case rect
        case text
        case highlight
        case blur
    }
}

// MARK: - Computed properties

extension Annotation {
    /// CGRect built from stored Double coordinates.
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// NSColor decoded from the stored hex string.
    var nsColor: NSColor {
        NSColor(hex: colorHex) ?? .systemRed
    }
}

// MARK: - Default colors

extension Annotation {
    static func defaultColorHex(for type: AnnotationType) -> String {
        switch type {
        case .arrow:     return "#FF3B30"  // system red
        case .rect:      return "#FF3B30"  // system red
        case .text:      return "#FF3B30"  // system red
        case .highlight: return "#FFD60A"  // system yellow
        case .blur:      return "#000000"  // unused, blur has no color
        }
    }
}

// MARK: - NSColor hex initialiser

private extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((value & 0xFF0000) >> 16) / 255
        let g = CGFloat((value & 0x00FF00) >> 8)  / 255
        let b = CGFloat(value & 0x0000FF)          / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
#endif
