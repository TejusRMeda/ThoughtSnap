#if os(macOS)
import XCTest
import AppKit
@testable import ThoughtSnap

// MARK: - AnnotationTests

final class AnnotationTests: XCTestCase {

    // MARK: - cgRect

    func testCGRectBuiltFromStoredDoubles() {
        let ann = Annotation(type: .rect, x: 10, y: 20, width: 100, height: 50)
        XCTAssertEqual(ann.cgRect, CGRect(x: 10, y: 20, width: 100, height: 50))
    }

    func testCGRectWithZeroSize() {
        let ann = Annotation(type: .arrow, x: 0, y: 0, width: 0, height: 0)
        XCTAssertEqual(ann.cgRect, .zero)
    }

    func testCGRectWithNegativeOrigin() {
        let ann = Annotation(type: .highlight, x: -5, y: -10, width: 40, height: 20)
        XCTAssertEqual(ann.cgRect.origin.x, -5, accuracy: 0.001)
        XCTAssertEqual(ann.cgRect.origin.y, -10, accuracy: 0.001)
    }

    // MARK: - nsColor

    func testNSColorParsesRedHex() {
        let ann = Annotation(type: .arrow, x: 0, y: 0, width: 0, height: 0, colorHex: "#FF0000")
        let color = ann.nsColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    func testNSColorFallsBackToRedOnBadHex() {
        let ann = Annotation(type: .rect, x: 0, y: 0, width: 0, height: 0, colorHex: "not-a-hex")
        // The fallback is .systemRed — just verify it doesn't crash and returns a color
        XCTAssertNotNil(ann.nsColor)
    }

    // MARK: - Default color hex

    func testDefaultColorHexForArrow() {
        XCTAssertEqual(Annotation.defaultColorHex(for: .arrow), "#FF3B30")
    }

    func testDefaultColorHexForHighlight() {
        XCTAssertEqual(Annotation.defaultColorHex(for: .highlight), "#FFD60A")
    }

    func testDefaultColorHexForBlur() {
        XCTAssertEqual(Annotation.defaultColorHex(for: .blur), "#000000")
    }

    // MARK: - AnnotationType

    func testAnnotationTypeRawValues() {
        XCTAssertEqual(Annotation.AnnotationType.arrow.rawValue,     "arrow")
        XCTAssertEqual(Annotation.AnnotationType.rect.rawValue,      "rect")
        XCTAssertEqual(Annotation.AnnotationType.text.rawValue,      "text")
        XCTAssertEqual(Annotation.AnnotationType.highlight.rawValue, "highlight")
        XCTAssertEqual(Annotation.AnnotationType.blur.rawValue,      "blur")
    }

    func testAnnotationTypeRoundTripsViaRawValue() {
        for type in Annotation.AnnotationType.allCases {
            let roundTripped = Annotation.AnnotationType(rawValue: type.rawValue)
            XCTAssertEqual(roundTripped, type)
        }
    }

    // MARK: - Codable round-trip

    func testAnnotationCodableRoundTrip() throws {
        let original = Annotation(
            id: UUID(),
            type: .text,
            x: 12.5,
            y: 34.0,
            width: 200,
            height: 80,
            colorHex: "#FFD60A",
            label: "Look here",
            strokeWidth: 3.0
        )
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Annotation.self, from: data)

        XCTAssertEqual(decoded.id,          original.id)
        XCTAssertEqual(decoded.type,        original.type)
        XCTAssertEqual(decoded.x,           original.x)
        XCTAssertEqual(decoded.y,           original.y)
        XCTAssertEqual(decoded.width,       original.width)
        XCTAssertEqual(decoded.height,      original.height)
        XCTAssertEqual(decoded.colorHex,    original.colorHex)
        XCTAssertEqual(decoded.label,       original.label)
        XCTAssertEqual(decoded.strokeWidth, original.strokeWidth)
    }

    // MARK: - Equatability

    func testAnnotationsWithSameIDAreEqual() {
        let id = UUID()
        let a1 = Annotation(id: id, type: .arrow, x: 0, y: 0, width: 10, height: 10)
        let a2 = Annotation(id: id, type: .arrow, x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(a1, a2)
    }

    func testAnnotationsWithDifferentIDsAreNotEqual() {
        let a1 = Annotation(type: .arrow, x: 0, y: 0, width: 10, height: 10)
        let a2 = Annotation(type: .arrow, x: 0, y: 0, width: 10, height: 10)
        XCTAssertNotEqual(a1, a2)
    }
}

// MARK: - AttachmentTests

final class AttachmentTests: XCTestCase {

    // MARK: - absoluteFileURL

    func testAbsoluteFileURLBuildsFromRelativePath() {
        let att = Attachment(type: .screenshot, filePath: "attachments/2026-04/test.png")
        let url = att.absoluteFileURL
        XCTAssertTrue(url.path.hasSuffix("attachments/2026-04/test.png"))
        XCTAssertTrue(url.isFileURL)
    }

    func testAbsoluteFileURLContainsThoughtSnapDirectory() {
        let att = Attachment(type: .image, filePath: "attachments/img.jpg")
        XCTAssertTrue(att.absoluteFileURL.path.contains("ThoughtSnap"))
    }

    // MARK: - thumbnailURL

    func testThumbnailURLHasThumbExtension() {
        let att = Attachment(type: .screenshot, filePath: "attachments/2026-04/abc.png")
        let thumb = att.thumbnailURL
        // Expected: …/abc.thumb.png
        XCTAssertTrue(thumb.path.contains(".thumb."))
    }

    func testThumbnailURLPreservesOriginalExtension() {
        let att = Attachment(type: .screenshot, filePath: "attachments/shot.png")
        XCTAssertEqual(att.thumbnailURL.pathExtension, "png")
    }

    func testThumbnailURLDiffersFromAbsoluteURL() {
        let att = Attachment(type: .screenshot, filePath: "attachments/unique.png")
        XCTAssertNotEqual(att.absoluteFileURL, att.thumbnailURL)
    }

    // MARK: - AttachmentType

    func testAttachmentTypeRawValues() {
        XCTAssertEqual(Attachment.AttachmentType.screenshot.rawValue, "screenshot")
        XCTAssertEqual(Attachment.AttachmentType.image.rawValue,      "image")
        XCTAssertEqual(Attachment.AttachmentType.audio.rawValue,      "audio")
    }

    func testAttachmentTypeRoundTripsViaRawValue() {
        let types: [Attachment.AttachmentType] = [.screenshot, .image, .audio]
        for t in types {
            XCTAssertEqual(Attachment.AttachmentType(rawValue: t.rawValue), t)
        }
    }

    // MARK: - Codable round-trip

    func testAttachmentCodableRoundTrip() throws {
        let original = Attachment(
            id: UUID(),
            type: .screenshot,
            filePath: "attachments/roundtrip.png",
            ocrText: "Hello OCR"
        )
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Attachment.self, from: data)

        XCTAssertEqual(decoded.id,       original.id)
        XCTAssertEqual(decoded.type,     original.type)
        XCTAssertEqual(decoded.filePath, original.filePath)
        XCTAssertEqual(decoded.ocrText,  original.ocrText)
    }
}

// MARK: - SLATrackerTests

final class SLATrackerTests: XCTestCase {

    // MARK: - Budget constants (mirror PRD §9)

    func testSLABudgets() {
        XCTAssertEqual(SLA.hotkeyToPanel,     500)
        XCTAssertEqual(SLA.screenshotPreview, 300)
        XCTAssertEqual(SLA.noteSave,          200)
        XCTAssertEqual(SLA.searchResults,     200)
        XCTAssertEqual(SLA.coldLaunch,       2_000)
    }

    // MARK: - Synchronous measure

    func testMeasureSyncReturnsWorkResult() {
        let result = SLATracker.measure(label: "test", budget: 1_000) { 42 }
        XCTAssertEqual(result, 42)
    }

    func testMeasureSyncWithThrowingWorkPropagatesError() {
        struct TestError: Error {}
        XCTAssertThrowsError(
            try SLATracker.measure(label: "test", budget: 1_000) { throw TestError() }
        )
    }

    func testMeasureSyncCompletesWithinBudget() {
        // Fast work: should be well under budget
        let start = CACurrentMediaTime()
        SLATracker.measure(label: "noop", budget: 1_000) { /* noop */ }
        let elapsed = (CACurrentMediaTime() - start) * 1_000
        XCTAssertLessThan(elapsed, 50, "Measurement overhead should be negligible")
    }

    // MARK: - Async measure

    func testMeasureAsyncReturnsWorkResult() async {
        let result = await SLATracker.measure(label: "async-test", budget: 1_000) {
            await Task.yield()
            return "hello"
        }
        XCTAssertEqual(result, "hello")
    }

    func testMeasureAsyncWithThrowingWorkPropagatesError() async {
        struct TestError: Error {}
        do {
            try await SLATracker.measure(label: "async-throw", budget: 1_000) {
                throw TestError()
            }
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is TestError)
        }
    }

    // MARK: - Manual start/stop

    func testManualStartStopDoesNotCrash() {
        let t0 = SLATracker.start()
        SLATracker.stop(since: t0, label: "manual", budget: 1_000)
    }

    // MARK: - Convenience wrappers

    func testMeasureHotkeyToPanelExecutesWork() {
        var called = false
        SLATracker.measureHotkeyToPanel { called = true }
        XCTAssertTrue(called)
    }

    func testMeasureNoteSaveExecutesWork() {
        var called = false
        SLATracker.measureNoteSave { called = true }
        XCTAssertTrue(called)
    }

    func testMeasureSearchExecutesWork() async {
        var called = false
        await SLATracker.measureSearch { called = true }
        XCTAssertTrue(called)
    }
}
#endif
