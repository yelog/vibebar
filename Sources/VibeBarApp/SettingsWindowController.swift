import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?
    private let viewState = SettingsViewState()
    private let windowPolicy = SettingsWindowPolicy.default

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
        window.contentMinSize = NSSize(
            width: windowPolicy.minContentSize.width,
            height: windowPolicy.minContentSize.height
        )
        window.contentMaxSize = NSSize(
            width: windowPolicy.maxContentSize.width,
            height: windowPolicy.maxContentSize.height
        )

        self.window = window
        self.viewState.window = window
        hostingController = hosting

        window.setContentSize(windowPolicy.defaultContentSize)

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsView() -> SettingsView {
        SettingsView(viewState: viewState)
    }
}
