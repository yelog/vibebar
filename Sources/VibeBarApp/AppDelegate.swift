import Darwin
import AppKit
import Combine
import VibeBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var agentProcess: Process?
    private var usageMonitor: UsageMonitorViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var terminationSignalSources: [DispatchSourceSignal] = []
    private var handledTerminationSignal = false
    private let agentLaunchCoordinator = AgentLaunchCoordinator()
    private let wrapperCommandInstaller = WrapperCommandInstaller()

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadAppIcon()
        setupMainMenu()
        prewarmWindowServerConnection()
        refreshManagedIntegrationBinaryIfNeeded()
        
        Task { @MainActor in
            await PricingManager.shared.initialize()
            usageMonitor = UsageMonitorViewModel.shared
            statusController = StatusItemController()
        }

        installSourceModeTerminationHandlersIfNeeded()
        startAgentIfNeeded()
        if VibeBarPaths.runMode == .published {
            UpdateChecker.shared.initialize()
        }

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
        if VibeBarPaths.runMode == .source {
            _ = agentLaunchCoordinator.cleanupAgentOnTerminate()
        } else if let process = agentProcess, process.isRunning {
            process.terminate()
        }
    }

    private func refreshManagedIntegrationBinaryIfNeeded() {
        do {
            _ = try wrapperCommandInstaller.prepareManagedBinaryForIntegrations()
        } catch {
            print("[AppDelegate] 无法刷新集成用 vibebar 二进制: \(error.localizedDescription)")
        }
    }

    // MARK: - Agent Auto-Start

    private func startAgentIfNeeded() {
        // Check if we're in the middle of an update - don't start agent
        if UpdateChecker.isUpdating {
            print("[AppDelegate] Skipping agent start during update process")
            return
        }
        
        let result = agentLaunchCoordinator.ensureAgentAvailable()
        if let process = result.process {
            agentProcess = process
        }
        if let error = result.error {
            print("[AppDelegate] 无法确保 vibebar-agent 可用: \(error.localizedDescription)")
        }
    }

    private func installSourceModeTerminationHandlersIfNeeded() {
        guard VibeBarPaths.runMode == .source else {
            return
        }

        registerTerminationSignal(SIGINT, exitCode: 130)
        registerTerminationSignal(SIGTERM, exitCode: 143)
    }

    private func registerTerminationSignal(_ signalNumber: Int32, exitCode: Int32) {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler { [weak self] in
            self?.handleTerminationSignal(exitCode: exitCode)
        }
        source.resume()
        terminationSignalSources.append(source)
    }

    private func handleTerminationSignal(exitCode: Int32) {
        guard !handledTerminationSignal else {
            return
        }
        handledTerminationSignal = true
        _ = agentLaunchCoordinator.cleanupAgentOnTerminate()
        exit(exitCode)
    }
}
