import AppKit
import VibeBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var agentProcess: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadAppIcon()
        setupMainMenu()
        statusController = StatusItemController()
        if VibeBarPaths.runMode == .published {
            startAgentIfNeeded()
        }
        UpdateChecker.shared.startAutoCheckIfNeeded()
    }

    // MARK: - Main Menu (for Cmd+Q / Cmd+W in accessory mode)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application menu (Cmd+Q)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 VibeBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu (Cmd+W)
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        NSApp.mainMenu = mainMenu
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
