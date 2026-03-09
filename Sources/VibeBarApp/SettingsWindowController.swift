import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private enum Layout {
        static let minWindowWidth: CGFloat = 450
        static let maxWindowWidth: CGFloat = 650
        static let minWindowHeight: CGFloat = 600
        static let maxWindowHeight: CGFloat = 900

        // Tab-specific dimensions (must match SettingsPanelLayout)
        static func contentWidth(for tab: SettingsTab) -> CGFloat {
            switch tab {
            case .cli:
                return 550  // 450 + 100
            default:
                return 450
            }
        }

        static func contentHeight(for tab: SettingsTab) -> CGFloat {
            switch tab {
            case .cli:
                return 690  // 790 - 100
            default:
                return 790
            }
        }

        static func windowContentSize(for tab: SettingsTab) -> NSSize {
            NSSize(width: contentWidth(for: tab), height: contentHeight(for: tab))
        }
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
        window.contentMinSize = NSSize(width: Layout.minWindowWidth, height: Layout.minWindowHeight)
        window.contentMaxSize = NSSize(width: Layout.maxWindowWidth, height: Layout.maxWindowHeight)

        self.window = window
        self.viewState.window = window
        hostingController = hosting

        // Set initial window size before showing
        let initialSize = Layout.windowContentSize(for: tab)
        window.setContentSize(initialSize)

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsView() -> SettingsView {
        SettingsView(viewState: viewState)
    }
}
