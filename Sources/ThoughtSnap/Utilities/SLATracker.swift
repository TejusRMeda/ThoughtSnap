#if os(macOS)
import Foundation
import QuartzCore

// MARK: - SLATracker
//
// Lightweight inline SLA measurement.  Use the `measure` functions at call-sites
// where the PRD specifies hard response-time budgets.  Violations are logged with
// a ⚠️ prefix so they're easily spotted in the Xcode console.
//
// All budgets (in milliseconds) mirror the values in PRD §9.

enum SLA {
    /// Hotkey press → panel visible
    static let hotkeyToPanel:    Double = 500
    /// Screenshot region mouse-up → preview rendered in panel
    static let screenshotPreview: Double = 300
    /// ⌘↩ → panel dismissed (note persisted)
    static let noteSave:          Double = 200
    /// Last search keystroke → results rendered
    static let searchResults:     Double = 200
    /// App process start → NSStatusItem visible
    static let coldLaunch:        Double = 2_000
}

enum SLATracker {

    // MARK: - Synchronous measure

    /// Runs `work`, logs a warning if it exceeds `budgetMs`, and returns the result.
    @discardableResult
    static func measure<T>(
        label: String,
        budget: Double,
        work: () throws -> T
    ) rethrows -> T {
        let t0     = CACurrentMediaTime()
        let result = try work()
        log(label: label, budget: budget, elapsed: (CACurrentMediaTime() - t0) * 1_000)
        return result
    }

    // MARK: - Async measure

    @discardableResult
    static func measure<T>(
        label: String,
        budget: Double,
        work: () async throws -> T
    ) async rethrows -> T {
        let t0     = CACurrentMediaTime()
        let result = try await work()
        log(label: label, budget: budget, elapsed: (CACurrentMediaTime() - t0) * 1_000)
        return result
    }

    // MARK: - Manual start / stop

    static func start() -> Double { CACurrentMediaTime() }

    static func stop(since t0: Double, label: String, budget: Double) {
        log(label: label, budget: budget, elapsed: (CACurrentMediaTime() - t0) * 1_000)
    }

    // MARK: - Private

    private static func log(label: String, budget: Double, elapsed: Double) {
        let rounded = String(format: "%.1f", elapsed)
        if elapsed > budget {
            print("⚠️  SLA VIOLATION [\(label)]: \(rounded)ms > \(Int(budget))ms budget")
        } else {
            #if DEBUG
            print("✅ SLA [\(label)]: \(rounded)ms (budget \(Int(budget))ms)")
            #endif
        }
    }
}

// MARK: - Convenience wrappers at known SLA points

extension SLATracker {

    static func measureHotkeyToPanel(_ work: () -> Void) {
        measure(label: "hotkey→panel", budget: SLA.hotkeyToPanel, work: work)
    }

    static func measureNoteSave(_ work: () -> Void) {
        measure(label: "note save",   budget: SLA.noteSave,  work: work)
    }

    static func measureSearch(_ work: () async -> Void) async {
        await measure(label: "search results", budget: SLA.searchResults, work: work)
    }
}
#endif
