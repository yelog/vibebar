import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private enum Layout {
        static let windowWidth: CGFloat = 450
        static let minContentHeight: CGFloat = 260
        static let resizeThreshold: CGFloat = 1
    }

    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var lastContentHeight: CGFloat = Layout.minContentHeight

    private init() {}

    func showSettings() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView { [weak self] height in
            self?.updateWindowSize(for: height)
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: Layout.windowWidth, height: Layout.minContentHeight)
        window.setContentSize(NSSize(width: Layout.windowWidth, height: Layout.minContentHeight))
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        hosting.view.layoutSubtreeIfNeeded()
        updateWindowSize(for: hosting.view.fittingSize.height)
    }

    private func updateWindowSize(for contentHeight: CGFloat) {
        guard let window else { return }

        let targetHeight = max(Layout.minContentHeight, ceil(contentHeight))
        guard abs(targetHeight - lastContentHeight) > Layout.resizeThreshold else { return }
        lastContentHeight = targetHeight

        let contentRect = NSRect(origin: .zero, size: NSSize(width: Layout.windowWidth, height: targetHeight))
        let targetFrameSize = window.frameRect(forContentRect: contentRect).size

        var frame = window.frame
        let deltaHeight = targetFrameSize.height - frame.size.height
        frame.origin.y -= deltaHeight
        frame.size = targetFrameSize

        window.setFrame(frame, display: true, animate: true)
    }
}
