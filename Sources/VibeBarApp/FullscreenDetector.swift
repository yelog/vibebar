import AppKit
import ApplicationServices
import Combine
import Foundation

/// Detects when other applications enter/exit fullscreen mode
///
/// Strategy:
/// - Uses NSWorkspace.activeSpaceDidChangeNotification to detect Space switches (fullscreen creates new Spaces)
/// - Debounces state changes to avoid flickering during transitions
/// - Quick to enter fullscreen (hide notch), slow to exit (avoid false positives)
@MainActor
final class FullscreenDetector: ObservableObject {
    static let shared = FullscreenDetector()

    /// Published state - only changes after debouncing
    @Published private(set) var isAnyAppInFullscreen = false

    /// Current raw detection state
    private var rawDetectedState = false

    private var cancellables = Set<AnyCancellable>()
    private var spaceChangeObserver: NSObjectProtocol?
    private var timer: Timer?
    private var debounceTask: Task<Void, Never>?

    /// Debounce delays to prevent flickering:
    /// - Entering fullscreen: 0.15s (quick hide)
    /// - Exiting fullscreen: 1.2s (wait for animation to complete)
    private let enterDelay: TimeInterval = 0.15
    private let exitDelay: TimeInterval = 1.2

    init() {
        // Set initial state before setting up observers
        rawDetectedState = detectFullscreenState()
        isAnyAppInFullscreen = rawDetectedState

        setupObservers()
        startTimer()
    }

    private func setupObservers() {
        // Primary: Space changes indicate fullscreen transitions
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Space change detected - check state multiple times during transition
            self?.handleSpaceChange()
        }
    }

    private func startTimer() {
        // Check every 0.5 seconds for state synchronization
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkAndUpdateState()
        }
        timer?.tolerance = 0.2
    }

    /// Called when Space changes (fullscreen transition start)
    private func handleSpaceChange() {
        // When Space changes, check immediately and once more after animation
        checkAndUpdateState()

        // One additional check after typical fullscreen animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkAndUpdateState()
        }
    }

    /// Check current state and update with debouncing
    private func checkAndUpdateState() {
        let newState = detectFullscreenState()

        // If no change, do nothing
        if newState == rawDetectedState { return }

        rawDetectedState = newState

        // Cancel any pending update
        debounceTask?.cancel()

        // Create new debounced update
        debounceTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            let delay = self.rawDetectedState ? self.enterDelay : self.exitDelay

            try? await Task.sleep(for: .seconds(delay))

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            // Only update if state is still the same after delay
            if self.isAnyAppInFullscreen != self.rawDetectedState {
                self.isAnyAppInFullscreen = self.rawDetectedState
            }
        }
    }

    /// Force immediate state update
    private func updateState() {
        let state = detectFullscreenState()
        rawDetectedState = state
        isAnyAppInFullscreen = state
    }

    /// Detects if frontmost app is in fullscreen
    private func detectFullscreenState() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        // Skip our own app
        if frontmostApp.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return false
        }

        return isAppInFullscreen(frontmostApp)
    }

    /// Checks if a specific app is currently in fullscreen
    private func isAppInFullscreen(_ app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        // Get focused window
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)

        guard result == .success, let window = windowRef else {
            return false
        }

        // Method 1: Check AXFullScreen attribute
        var fullscreenValue: CFTypeRef?
        let fsResult = AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            "AXFullScreen" as CFString,
            &fullscreenValue
        )

        if fsResult == .success, let isFullscreen = fullscreenValue as? Bool {
            return isFullscreen
        }

        // Method 2: Check window size matches screen
        return checkWindowFullscreenBySize(window as! AXUIElement)
    }

    /// Fallback: Check if window occupies full screen
    private func checkWindowFullscreenBySize(_ windowRef: AXUIElement) -> Bool {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        let posResult = AXUIElementCopyAttributeValue(windowRef, kAXPositionAttribute as CFString, &posRef)
        let sizeResult = AXUIElementCopyAttributeValue(windowRef, kAXSizeAttribute as CFString, &sizeRef)

        guard posResult == .success, sizeResult == .success else {
            return false
        }

        var origin: CGPoint = .zero
        var size: CGSize = .zero

        if let pos = posRef {
            AXValueGetValue(pos as! AXValue, .cgPoint, &origin)
        }
        if let sz = sizeRef {
            AXValueGetValue(sz as! AXValue, .cgSize, &size)
        }

        guard let screen = NSScreen.main else { return false }

        let screenFrame = screen.frame
        let windowFrame = CGRect(origin: origin, size: size)

        // Use 30 point tolerance for fullscreen detection
        let tolerance: CGFloat = 30.0

        return abs(windowFrame.width - screenFrame.width) < tolerance &&
               abs(windowFrame.height - screenFrame.height) < tolerance &&
               abs(windowFrame.minX - screenFrame.minX) < tolerance &&
               abs(windowFrame.minY - screenFrame.minY) < tolerance
    }
}
