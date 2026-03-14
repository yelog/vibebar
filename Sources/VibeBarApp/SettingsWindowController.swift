import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private enum Layout {
        static let minWindowHeight: CGFloat = 600
        static let maxWindowHeight: CGFloat = 900
    }

    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?
    private let viewState = SettingsViewState()

    private init() {}

    func showSettings(tab: SettingsTab = .general) {
        viewState.selectedTab = tab

        if let window, let hostingController {
            hostingController.view.layoutSubtreeIfNeeded()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: makeSettingsView())

        // Disable automatic window resizing by NSHostingController
        hosting.sizingOptions = []

        let window = NSWindow(contentViewController: hosting)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: SettingsPanelLayout.minWindowWidth, height: Layout.minWindowHeight)
        window.contentMaxSize = NSSize(width: SettingsPanelLayout.maxWindowWidth, height: Layout.maxWindowHeight)

        self.window = window
        self.viewState.window = window
        hostingController = hosting

        // Set initial window size before showing
        let initialSize = SettingsPanelLayout.windowContentSize(for: tab)
        window.setContentSize(initialSize)

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsView() -> SettingsView {
        SettingsView(viewState: viewState)
    }
}
