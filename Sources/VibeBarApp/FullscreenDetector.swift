import AppKit
import ApplicationServices
import Combine
import Foundation

import VibeBarCore

/// Detects when other applications enter/exit fullscreen mode
///
/// Strategy:
/// - Uses NSWorkspace.activeSpaceDidChangeNotification to detect Space switches (fullscreen creates new Spaces)
/// - Uses NSWorkspace.didActivateApplicationNotification to react to application activation
/// - Debounces state changes to avoid flickering during transitions
/// - Quick to enter fullscreen (hide notch), slow to exit (avoid false positives)
/// - Notification-driven: no repeating timer is installed, so idle operation costs no wakeups.
@MainActor
final class FullscreenDetector: ObservableObject {
    /// Schedules a delayed action without blocking the caller. Tests inject a
    /// scheduler that records actions instead of sleeping.
    typealias DelayedActionScheduler = @Sendable (
        Duration,
        @escaping @MainActor @Sendable () -> Void
    ) -> Void

    /// Published state - only changes after debouncing
    @Published private(set) var isAnyAppInFullscreen = false

    /// Current raw detection state
    private var rawDetectedState = false

    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    /// Monotonic generation counter that invalidates stale scheduled actions
    /// after a state change or after `stop()`.
    private var generation = 0
    private var isStopped = false

    /// Debounce delays to prevent flickering:
    /// - Entering fullscreen: 0.15s (quick hide)
    /// - Exiting fullscreen: 1.2s (wait for animation to complete)
    private let enterDelay: Duration = .milliseconds(150)
    private let exitDelay: Duration = .milliseconds(1200)
    /// Additional verification after a Space transition completes.
    private let spaceVerifyDelay: Duration = .seconds(1)

    private let detect: @MainActor () -> Bool
    private let notificationCenter: NotificationCenter
    private let scheduler: DelayedActionScheduler

    init(
        detect: @escaping @MainActor () -> Bool = { FullscreenDetector.defaultDetect() },
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        scheduler: @escaping DelayedActionScheduler = FullscreenDetector.defaultScheduler
    ) {
        self.detect = detect
        self.notificationCenter = notificationCenter
        self.scheduler = scheduler

        // Set initial state before setting up observers
        rawDetectedState = detect()
        isAnyAppInFullscreen = rawDetectedState

        setupObservers()
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    /// Removes observers and neutralizes any pending scheduled verification.
    func stop() {
        isStopped = true
        generation += 1
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func setupObservers() {
        // Primary: Space changes indicate fullscreen transitions
        observers.append(notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Self.runOnMain {
                self?.handleSpaceChange()
            }
        })

        // Secondary: application activation can change the frontmost window state
        observers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Self.runOnMain {
                self?.handleApplicationActivation()
            }
        })
    }

    private nonisolated static func runOnMain(_ action: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(action)
        } else {
            Task { @MainActor in
                action()
            }
        }
    }

    /// Called when Space changes (fullscreen transition start)
    private func handleSpaceChange() {
        guard !isStopped else { return }

        // When Space changes, check immediately and once more after animation
        checkAndUpdateState()
        scheduleDelayedVerification()
    }

    private func handleApplicationActivation() {
        guard !isStopped else { return }
        checkAndUpdateState()
    }

    /// One additional check after typical fullscreen animation completes.
    private func scheduleDelayedVerification() {
        let currentGeneration = generation
        scheduler(spaceVerifyDelay) { [weak self] in
            guard let self,
                  !self.isStopped,
                  currentGeneration == self.generation else {
                return
            }
            self.checkAndUpdateState()
        }
    }

    /// Check current state and update with debouncing
    private func checkAndUpdateState() {
        guard !isStopped else { return }

        let newState = detect()

        // If no change, do nothing
        if newState == rawDetectedState { return }

        rawDetectedState = newState
        generation += 1
        let currentGeneration = generation

        // Create new debounced update
        let delay = rawDetectedState ? enterDelay : exitDelay
        scheduler(delay) { [weak self] in
            guard let self,
                  !self.isStopped,
                  currentGeneration == self.generation else {
                return
            }
            // Only update if state is still the same after delay
            if self.isAnyAppInFullscreen != self.rawDetectedState {
                self.isAnyAppInFullscreen = self.rawDetectedState
            }
        }
    }

    private nonisolated static func defaultScheduler(
        _ duration: Duration,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) {
        Task { @MainActor in
            do {
                try await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                action()
            } catch {
                // Cancelled or interrupted.
            }
        }
    }

    private static func defaultDetect() -> Bool {
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
    private static func isAppInFullscreen(_ app: NSRunningApplication) -> Bool {
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
    private static func checkWindowFullscreenBySize(_ windowRef: AXUIElement) -> Bool {
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