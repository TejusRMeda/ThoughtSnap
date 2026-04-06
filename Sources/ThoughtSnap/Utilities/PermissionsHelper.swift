#if os(macOS)
import AppKit
import CoreGraphics

// MARK: - PermissionsHelper

/// Checks and requests macOS permissions required by ThoughtSnap.
/// Should be called from AppDelegate.applicationDidFinishLaunching.
enum PermissionsHelper {

    // MARK: - Screen Recording

    /// Returns true if screen recording permission is currently granted.
    static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Requests screen recording permission.
    /// IMPORTANT: macOS only reflects the grant after the app is relaunched.
    /// Show an alert telling the user to quit and relaunch after granting.
    static func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Accessibility (required for global hotkey via CGEvent tap)

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Combined check on launch

    static func checkAndRequestPermissions() {
        checkScreenRecording()
        checkAccessibility()
    }

    // MARK: - Private

    private static func checkScreenRecording() {
        guard !hasScreenRecordingPermission() else { return }

        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
            ThoughtSnap needs Screen Recording permission to capture screenshots.

            After clicking "Open System Settings", grant permission to ThoughtSnap, \
            then quit and relaunch the app for the change to take effect.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
            // Trigger the system permission dialog too
            requestScreenRecordingPermission()
        }
    }

    private static func checkAccessibility() {
        guard !hasAccessibilityPermission() else { return }

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            ThoughtSnap needs Accessibility permission to register the global hotkey \
            (⌘⇧Space) so you can capture thoughts from any app.

            Click "Open System Settings" and enable ThoughtSnap in the \
            Privacy & Security → Accessibility list.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
}
#endif
