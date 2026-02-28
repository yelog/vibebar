import AppKit
import Combine
import VibeBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var agentProcess: Process?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadAppIcon()
        setupMainMenu()
        prewarmWindowServerConnection()
        statusController = StatusItemController()
        if VibeBarPaths.runMode == .published {
            startAgentIfNeeded()
        }
        // Initialize Sparkle auto-updater
        UpdateChecker.shared.initialize()
        UpdateChecker.shared.startAutoCheckIfNeeded()

        L10n.shared.$resolvedLang
            .dropFirst()
            .sink { [weak self] _ in
                self?.setupMainMenu()
            }
            .store(in: &cancellables)
    }

    // MARK: - Main Menu (for Cmd+Q / Cmd+W in accessory mode)

    private func setupMainMenu() {
        let l10n = L10n.shared
        let mainMenu = NSMenu()

        // Application menu (Cmd+Q)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: l10n.string(.quitVibeBar), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu (Cmd+W)
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: l10n.string(.closeWindow), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - WindowServer Pre-warm

    /// Forces an early WindowServer connection to avoid the ~1s Hardened Runtime
    /// security check delay that would otherwise occur on the first menu bar click.
    /// The check only affects signed builds with `--options runtime`; `swift run`
    /// (unsigned) is unaffected. By triggering the check at launch we pay the cost
    /// once during startup, where it is far less noticeable.
    private func prewarmWindowServerConnection() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.orderFront(nil)
        window.orderOut(nil)
    }

    // MARK: - App Icon

    private func loadAppIcon() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let process = agentProcess, process.isRunning {
            process.terminate()
        }
    }

    // MARK: - Agent Auto-Start

    private func startAgentIfNeeded() {
        // Check if vibebar-agent is already running
        if isAgentRunning() { return }

        let exe = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()
        let agentURL = exe.deletingLastPathComponent()
            .appendingPathComponent("vibebar-agent")
        guard FileManager.default.isExecutableFile(atPath: agentURL.path) else { return }

        let process = Process()
        process.executableURL = agentURL
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            agentProcess = process
        } catch {
            // Silently fail — agent can be started manually
        }
    }

    private func isAgentRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "vibebar-agent"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
