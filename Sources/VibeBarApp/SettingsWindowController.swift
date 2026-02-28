import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private enum Layout {
        static let windowWidth: CGFloat = 580
        static let fixedContentHeight: CGFloat = 750
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
            window.setContentSize(NSSize(width: Layout.windowWidth, height: Layout.fixedContentHeight))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: makeSettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: Layout.windowWidth, height: Layout.fixedContentHeight)
        window.contentMaxSize = NSSize(width: Layout.windowWidth, height: Layout.fixedContentHeight)
        window.setContentSize(NSSize(width: Layout.windowWidth, height: Layout.fixedContentHeight))

        self.window = window
        hostingController = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsView() -> SettingsView {
        SettingsView(viewState: viewState)
    }
}
