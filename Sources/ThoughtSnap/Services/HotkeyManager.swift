#if os(macOS)
import Foundation
import AppKit
import HotKey
import Combine

// MARK: - KeyComboPreference

/// Serialisable representation of a key combination stored in UserDefaults.
struct KeyComboPreference: Codable {
    let keyCode: UInt32
    let modifiers: UInt
}

// MARK: - HotkeyManager

/// Registers and manages the global hotkey that shows the capture panel.
/// Exposes a Combine publisher so AppDelegate can subscribe to hotkey events.
final class HotkeyManager: ObservableObject {

    // MARK: Published state

    @Published private(set) var isRegistered: Bool = false

    // MARK: Publisher

    /// Fires on the main queue whenever the hotkey is pressed.
    let hotkeyFired = PassthroughSubject<Void, Never>()

    // MARK: Private

    private var hotKey: HotKey?
    private let defaultsKey = "com.thoughtsnap.hotkey"

    // MARK: - Initialisation

    init() {
        // Hotkey registration must happen after NSApp is running.
        // Call register() from AppDelegate.applicationDidFinishLaunching.
    }

    // MARK: - Registration

    /// Registers the hotkey. Uses the persisted preference if available,
    /// otherwise falls back to the default ⌘⇧Space.
    func register() {
        let combo = loadStoredCombo() ?? defaultCombo()
        register(combo: combo)
    }

    func register(combo: KeyCombo) {
        hotKey = nil  // deregister previous

        hotKey = HotKey(keyCombo: combo)
        hotKey?.keyDownHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.hotkeyFired.send()
            }
        }

        isRegistered = true
        persist(combo: combo)
        print("[HotkeyManager] Registered hotkey: \(combo)")
    }

    func unregister() {
        hotKey = nil
        isRegistered = false
    }

    // MARK: - Default combo

    private func defaultCombo() -> KeyCombo {
        // Default: ⌘⇧Space
        KeyCombo(key: .space, modifiers: [.command, .shift])
    }

    // MARK: - Persistence

    private func persist(combo: KeyCombo) {
        let pref = KeyComboPreference(
            keyCode: UInt32(combo.key.carbonKeyCode),
            modifiers: combo.modifiers.rawValue
        )
        if let data = try? JSONEncoder().encode(pref) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func loadStoredCombo() -> KeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let pref = try? JSONDecoder().decode(KeyComboPreference.self, from: data),
              let key = Key(carbonKeyCode: UInt32(pref.keyCode))
        else { return nil }

        let modifiers = NSEvent.ModifierFlags(rawValue: pref.modifiers)
        return KeyCombo(key: key, modifiers: modifiers)
    }
}
#endif
