#if os(macOS)
import SwiftUI
import AppKit
import Combine

// MARK: - App Entry Point

@main
struct ThoughtSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The main window and capture panel are managed imperatively in AppDelegate
        // using NSPanel / NSWindow so we can control window level, collection behavior,
        // and canBecomeKey — none of which are possible with SwiftUI WindowGroup.
        //
        // Settings window is the only scene managed declaratively.
        Settings {
            SettingsView()
                .environmentObject(appDelegate.storageService)
                .environmentObject(appDelegate.hotkeyManager)
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    // MARK: Services (injected into SwiftUI environment)

    let storageService = StorageService()
    let hotkeyManager  = HotkeyManager()

    // MARK: UI

    private var statusItem: NSStatusItem?
    private var capturePanelController: CapturePanelController?
    private var mainWindowController: MainWindowController?

    // MARK: Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Run as accessory (menubar only — no Dock icon) until main window is shown.
        NSApp.activationPolicy = .accessory

        // 2. Set up the menubar icon.
        setupStatusItem()

        // 3. Pre-warm the capture panel so the first hotkey press is fast.
        //    The panel is created hidden; orderFront is called on hotkey.
        capturePanelController = CapturePanelController(
            storageService: storageService
        )

        // 4. Register the global hotkey.
        hotkeyManager.register()
        hotkeyManager.hotkeyFired
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.showCapturePanel() }
            .store(in: &cancellables)

        // 5. Check permissions — non-blocking; shows advisory alerts if needed.
        PermissionsHelper.checkAndRequestPermissions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The app lives in the menubar; closing the main window should not quit.
        false
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "brain.head.profile",
                accessibilityDescription: "ThoughtSnap"
            )
            button.image?.isTemplate = true  // respects menu bar appearance (light/dark)
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleMainWindow()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture (⌘⇧Space)", action: #selector(showCapturePanel), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open ThoughtSnap", action: #selector(toggleMainWindow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ThoughtSnap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil  // clear so left-click works next time
    }

    // MARK: - Actions

    @objc func showCapturePanel() {
        capturePanelController?.show()
    }

    @objc func toggleMainWindow() {
        if let wc = mainWindowController, wc.window?.isVisible == true {
            wc.window?.orderOut(nil)
        } else {
            openMainWindow()
        }
    }

    private func openMainWindow() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController(
                storageService: storageService,
                capturePanelController: capturePanelController
            )
        }
        // Switch to regular policy so the app appears in the Dock while the main window is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - MainWindowController

/// Thin wrapper that reverts to .accessory policy when the main window closes.
/// Subscribes to .showCapturePanel so the ⌘N button in TimelineView works.
final class MainWindowController: NSWindowController, NSWindowDelegate {

    private let storageService: StorageService
    private var capturePanelController: CapturePanelController?
    private var showCapturePanelObserver: Any?

    init(storageService: StorageService, capturePanelController: CapturePanelController?) {
        self.storageService = storageService
        self.capturePanelController = capturePanelController

        let windowVM    = MainWindowViewModel()
        let contentView = MainWindowView()
            .environmentObject(storageService)
            .environmentObject(windowVM)

        let hosting = NSHostingController(rootView: contentView)
        let window  = NSWindow(contentViewController: hosting)
        window.title    = "ThoughtSnap"
        window.setContentSize(NSSize(width: 1020, height: 660))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.minSize   = NSSize(width: 760, height: 520)
        window.center()
        super.init(window: window)
        window.delegate = self

        showCapturePanelObserver = NotificationCenter.default.addObserver(
            forName: .showCapturePanel,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            self?.capturePanelController?.show()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit {
        if let obs = showCapturePanelObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Main window content

/// Three-column NavigationSplitView:
///   Column 1 — SidebarView   (spaces, tags, filters, search)
///   Column 2 — TimelineView  (date-grouped note list / search results)
///   Column 3 — NoteDetailView (selected note body + backlinks)
private struct MainWindowView: View {
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var windowVM:       MainWindowViewModel

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView()
                .environmentObject(storageService)
                .environmentObject(windowVM)
        } content: {
            TimelineView()
                .environmentObject(storageService)
                .environmentObject(windowVM)
        } detail: {
            if let noteID = windowVM.selectedNoteID {
                NoteDetailView(noteID: noteID)
                    .environmentObject(storageService)
                    .environmentObject(windowVM)
            } else {
                noSelectionPlaceholder
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var noSelectionPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Select a note to read it")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("Press ⌘⇧Space to capture a new thought from anywhere.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Placeholder settings view — fleshed out in Week 6.
private struct SettingsView: View {
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var hotkeyManager: HotkeyManager

    var body: some View {
        Form {
            Text("Settings coming in v0.1 polish phase.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}
#endif
