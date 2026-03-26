import AppKit
import SwiftUI
import VibeBarCore

@MainActor
final class NotchDisplayController {
    private static let forcedAppearance = NSAppearance(named: .darkAqua)

    private struct NotchGeometry {
        var notchFrame: NSRect
        var safeAreaTopInset: CGFloat
    }

    private struct TopPanelLayout {
        var frame: NSRect
        var presentation: NotchCollapsedView.Presentation
    }

    struct Payload {
        var summary: GlobalSummary
        var model: MonitorViewModel
        var usageSnapshot: UsageSnapshot?
        var usageEnabled: Bool
        var isUsageRefreshing: Bool
    }

    private enum Layout {
        static let extensionWidth: CGFloat = 34
        static let estimatedNotchWidth: CGFloat = 200
        static let estimatedNotchHeight: CGFloat = 30
        static let hotZoneBottomOverflow: CGFloat = 12
        static let bridgePanelOverlap: CGFloat = 8
        static let screenInset: CGFloat = 8
        static let pointerHitSlop: CGFloat = 2
        static let expandedAnimationDuration: TimeInterval = 0.28
        static let collapsedAnimationDuration: TimeInterval = 0.18
        static let fallbackMaximumPanelHeight: CGFloat = 560
    }

    var onExpandedStateChange: ((Bool) -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private let collapsedPanel: NSPanel
    private let expandedPanel: NSPanel
    private let collapsedContainerView: NotchTrackingContainerView
    private let expandedContainerView: NotchTrackingContainerView
    private let collapsedHostingView: NSHostingView<NotchCollapsedView>
    private let expandedHostingView: NSHostingView<NotchContentView>

    private var hoverStateMachine = NotchHoverStateMachine()
    private var expandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var localMouseMoveMonitor: Any?
    private var globalMouseMoveMonitor: Any?
    private(set) var isExpanded = false
    private var currentGeometry: NotchGeometry?
    private var topPanelPresentation: NotchCollapsedView.Presentation = .collapsed(
        notchWidth: Layout.estimatedNotchWidth,
        extensionWidth: Layout.extensionWidth,
        notchHeight: Layout.estimatedNotchHeight
    )
    private var payload = Payload(
        summary: GlobalSummary(total: 0, counts: [:], byTool: [:], updatedAt: Date()),
        model: MonitorViewModel.shared,
        usageSnapshot: nil,
        usageEnabled: false,
        isUsageRefreshing: false
    )

    init() {
        collapsedHostingView = NSHostingView(
            rootView: NotchCollapsedView(summary: payload.summary, presentation: topPanelPresentation)
        )
        expandedHostingView = NSHostingView(
            rootView: NotchContentView(
                summary: payload.summary,
                model: payload.model,
                usageSnapshot: payload.usageSnapshot,
                usageEnabled: payload.usageEnabled,
                isUsageRefreshing: payload.isUsageRefreshing,
                contentTopInset: Layout.estimatedNotchHeight,
                topCoverPresentation: .bridge(
                    surfaceX: Layout.estimatedNotchWidth,
                    extensionWidth: Layout.extensionWidth,
                    notchHeight: Layout.estimatedNotchHeight,
                    visibleHeight: Layout.estimatedNotchHeight + Layout.bridgePanelOverlap
                ),
                onRefresh: {},
                onOpenSettings: {},
                onQuit: {}
            )
        )

        collapsedContainerView = NotchTrackingContainerView()
        expandedContainerView = NotchTrackingContainerView()
        collapsedPanel = Self.makePanel(hasShadow: false)
        expandedPanel = Self.makePanel(hasShadow: true)

        installCollapsedContent()
        installExpandedContent()
        applyForcedAppearance()
        configureTracking()
    }

    func show(payload: Payload) {
        self.payload = payload
        installPointerMonitorsIfNeeded()
        _ = updateGeometry()
        refreshContent()
        positionCollapsedPanel()
        collapsedPanel.alphaValue = 1
        collapsedPanel.orderFrontRegardless()
    }

    func update(payload: Payload) {
        self.payload = payload
        guard let geometry = updateGeometry() else { return }
        refreshContent()

        if expandedPanel.isVisible || isExpanded {
            let finalFrame = expandedPanelFrame(using: geometry)
            if expandedPanel.isVisible {
                expandedPanel.setFrame(finalFrame, display: false)
            }
            collapsedPanel.orderOut(nil)
        } else if collapsedPanel.isVisible {
            applyTopPanelLayout(collapsedTopPanelLayout(using: geometry))
        }
    }

    func hide() {
        cancelTimers()
        removePointerMonitors()
        hoverStateMachine = NotchHoverStateMachine()
        if isExpanded {
            isExpanded = false
            onExpandedStateChange?(false)
        }
        topPanelPresentation = .collapsed(
            notchWidth: Layout.estimatedNotchWidth,
            extensionWidth: Layout.extensionWidth,
            notchHeight: Layout.estimatedNotchHeight
        )
        collapsedPanel.orderOut(nil)
        expandedPanel.orderOut(nil)
    }

    func expandFromNotification(payload: Payload) {
        self.payload = payload
        installPointerMonitorsIfNeeded()
        _ = updateGeometry()
        refreshContent()
        positionCollapsedPanel()
        collapsedPanel.alphaValue = 1
        collapsedPanel.orderFrontRegardless()
        cancelTimers()
        expandImmediately()
    }

    func collapse() {
        guard isExpanded else { return }
        collapseImmediately()
    }

    private func installCollapsedContent() {
        collapsedContainerView.wantsLayer = true
        collapsedHostingView.autoresizingMask = [.width, .height]
        collapsedContainerView.addSubview(collapsedHostingView)
        collapsedPanel.contentView = collapsedContainerView
    }

    private func installExpandedContent() {
        expandedContainerView.wantsLayer = true
        expandedContainerView.addSubview(expandedHostingView)
        expandedPanel.contentView = expandedContainerView
        refreshExpandedPanelLayout()
    }

    private func applyForcedAppearance() {
        guard let appearance = Self.forcedAppearance else { return }
        collapsedPanel.appearance = appearance
        expandedPanel.appearance = appearance
        collapsedContainerView.appearance = appearance
        expandedContainerView.appearance = appearance
        collapsedHostingView.appearance = appearance
        expandedHostingView.appearance = appearance
    }

    private func configureTracking() {
        collapsedContainerView.onPointerEntered = { [weak self] in
            self?.reconcilePointerPresence()
        }
        collapsedContainerView.onPointerExited = { [weak self] in
            self?.reconcilePointerPresence()
        }
        expandedContainerView.onPointerEntered = { [weak self] in
            self?.reconcilePointerPresence()
        }
        expandedContainerView.onPointerExited = { [weak self] in
            self?.reconcilePointerPresence()
        }
    }

    private func installPointerMonitorsIfNeeded() {
        if localMouseMoveMonitor == nil {
            localMouseMoveMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            ) { [weak self] event in
                self?.reconcilePointerPresence()
                return event
            }
        }

        if globalMouseMoveMonitor == nil {
            globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.reconcilePointerPresence()
                }
            }
        }
    }

    private func removePointerMonitors() {
        if let localMouseMoveMonitor {
            NSEvent.removeMonitor(localMouseMoveMonitor)
            self.localMouseMoveMonitor = nil
        }

        if let globalMouseMoveMonitor {
            NSEvent.removeMonitor(globalMouseMoveMonitor)
            self.globalMouseMoveMonitor = nil
        }
    }

    private func handleHoverEvent(_ event: NotchHoverStateMachine.Event) {
        let effect = hoverStateMachine.reduce(event)
        apply(effect: effect)
    }

    private func reconcilePointerPresence() {
        let pointerInHotZone = isPointerInsideVisiblePanel()
        handleHoverEvent(pointerInHotZone ? .pointerEnteredHotZone : .pointerExitedAllZones)
    }

    private func isPointerInsideVisiblePanel() -> Bool {
        let mouseLocation = NSEvent.mouseLocation
        if let geometry = currentGeometry, expandedPanel.isVisible || isExpanded {
            let panelSize = expandedContainerView.frame.size == .zero
                ? expandedPanel.frame.size
                : expandedContainerView.frame.size
            let targetFrame = expandedPanelFrame(using: geometry, panelSize: panelSize)
            if expandedHitFrame(for: targetFrame).contains(mouseLocation) {
                return true
            }
        }
        if collapsedPanel.isVisible,
           expandedHitFrame(for: collapsedPanel.frame).contains(mouseLocation) {
            return true
        }
        return false
    }

    private func expandedHitFrame(for frame: NSRect) -> NSRect {
        frame.insetBy(dx: -Layout.pointerHitSlop, dy: -Layout.pointerHitSlop)
    }

    private func apply(effect: NotchHoverStateMachine.Effect) {
        switch effect {
        case .none:
            break
        case .scheduleExpand:
            scheduleExpand()
        case .cancelExpand:
            expandWorkItem?.cancel()
            expandWorkItem = nil
        case .scheduleCollapse:
            scheduleCollapse()
        case .cancelCollapse:
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
        case .expandNow:
            expandImmediately()
        case .collapseNow:
            collapseImmediately()
        }
    }

    private func scheduleExpand() {
        expandWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let effect = self.hoverStateMachine.reduce(.expandTimerFired)
            self.apply(effect: effect)
        }
        expandWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(NotchHoverTiming.expandDelayMilliseconds),
            execute: workItem
        )
    }

    private func scheduleCollapse() {
        collapseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let effect = self.hoverStateMachine.reduce(.collapseTimerFired)
            self.apply(effect: effect)
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(NotchHoverTiming.collapseDelayMilliseconds),
            execute: workItem
        )
    }

    private func cancelTimers() {
        expandWorkItem?.cancel()
        expandWorkItem = nil
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    private func expandImmediately() {
        guard let geometry = updateGeometry() else { return }
        cancelTimers()
        refreshContent()
        refreshExpandedPanelLayout()

        let finalFrame = expandedPanelFrame(using: geometry)
        let startFrame = animationSeedFrame(using: geometry)
        expandedPanel.setFrame(startFrame, display: true)
        expandedPanel.alphaValue = 1
        expandedPanel.orderFrontRegardless()
        collapsedPanel.orderOut(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.expandedAnimationDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            context.allowsImplicitAnimation = true
            expandedPanel.animator().setFrame(finalFrame, display: true)
        } completionHandler: {
            Task { @MainActor in
                self.reconcilePointerPresence()
            }
        }

        if !isExpanded {
            isExpanded = true
            onExpandedStateChange?(true)
        }
    }

    private func collapseImmediately() {
        guard let geometry = updateGeometry() else { return }
        cancelTimers()
        let finalFrame = animationSeedFrame(using: geometry)
        collapsedPanel.orderOut(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.collapsedAnimationDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            context.allowsImplicitAnimation = true
            expandedPanel.animator().setFrame(finalFrame, display: true)
        } completionHandler: {
            Task { @MainActor in
                self.applyTopPanelLayout(self.collapsedTopPanelLayout(using: geometry))
                self.collapsedPanel.alphaValue = 1
                self.collapsedPanel.orderFrontRegardless()
                self.expandedPanel.orderOut(nil)
                self.expandedPanel.alphaValue = 1
                self.reconcilePointerPresence()
            }
        }

        if isExpanded {
            isExpanded = false
            onExpandedStateChange?(false)
        }
    }

    private func refreshContent() {
        collapsedHostingView.rootView = NotchCollapsedView(
            summary: payload.summary,
            presentation: topPanelPresentation
        )
        expandedHostingView.rootView = NotchContentView(
            summary: payload.summary,
            model: payload.model,
            usageSnapshot: payload.usageSnapshot,
            usageEnabled: payload.usageEnabled,
            isUsageRefreshing: payload.isUsageRefreshing,
            contentTopInset: expandedContentTopInset(),
            topCoverPresentation: expandedTopCoverPresentation(),
            onRefresh: { [weak self] in self?.onRefresh?() },
            onOpenSettings: { [weak self] in self?.onOpenSettings?() },
            onQuit: { [weak self] in self?.onQuit?() }
        )
        refreshExpandedPanelLayout()
    }

    private func refreshExpandedPanelLayout() {
        expandedHostingView.layoutSubtreeIfNeeded()
        let fittingSize = expandedHostingView.fittingSize
        let maximumHeight = maximumExpandedPanelHeight()
        let size = NSSize(
            width: max(fittingSize.width, 440),
            height: min(fittingSize.height, maximumHeight)
        )
        expandedContainerView.frame = NSRect(origin: .zero, size: size)
        expandedHostingView.frame = NSRect(origin: .zero, size: size)
        expandedPanel.setContentSize(size)
    }

    private func expandedContentTopInset() -> CGFloat {
        let notchHeight = currentGeometry?.notchFrame.height ?? Layout.estimatedNotchHeight
        let safeAreaTopInset = currentGeometry?.safeAreaTopInset ?? 0
        return max(notchHeight, safeAreaTopInset, Layout.bridgePanelOverlap)
    }

    private func expandedTopCoverPresentation() -> NotchCollapsedView.Presentation {
        guard let geometry = currentGeometry else {
            return .bridge(
                surfaceX: Layout.estimatedNotchWidth,
                extensionWidth: Layout.extensionWidth,
                notchHeight: Layout.estimatedNotchHeight,
                visibleHeight: Layout.estimatedNotchHeight + Layout.bridgePanelOverlap
            )
        }

        let panelSize = NSSize(
            width: max(expandedPanel.frame.width, 440),
            height: max(expandedPanel.frame.height, 1)
        )
        let finalPanelFrame = expandedPanelFrame(using: geometry, panelSize: panelSize)
        return bridgeTopPanelLayout(using: geometry, finalPanelFrame: finalPanelFrame).presentation
    }

    private func maximumExpandedPanelHeight() -> CGFloat {
        guard let geometry = currentGeometry,
              let screen = primaryScreen() else {
            return Layout.fallbackMaximumPanelHeight
        }

        let availableHeight = geometry.notchFrame.maxY - screen.visibleFrame.minY - Layout.screenInset
        return max(availableHeight, 240)
    }

    private func positionCollapsedPanel() {
        guard let geometry = updateGeometry() else { return }
        applyTopPanelLayout(collapsedTopPanelLayout(using: geometry))
    }

    private func applyTopPanelLayout(_ layout: TopPanelLayout, animated: Bool = false) {
        topPanelPresentation = layout.presentation
        collapsedHostingView.rootView = NotchCollapsedView(
            summary: payload.summary,
            presentation: layout.presentation
        )
        collapsedContainerView.frame = NSRect(origin: .zero, size: layout.frame.size)
        collapsedHostingView.frame = collapsedContainerView.bounds
        collapsedPanel.setContentSize(layout.frame.size)
        if animated {
            collapsedPanel.animator().setFrame(layout.frame, display: true)
        } else {
            collapsedPanel.setFrame(layout.frame, display: false)
        }
    }

    private func collapsedTopPanelLayout(using geometry: NotchGeometry) -> TopPanelLayout {
        let frame = NSRect(
            x: geometry.notchFrame.minX,
            y: geometry.notchFrame.minY - Layout.hotZoneBottomOverflow,
            width: geometry.notchFrame.width + Layout.extensionWidth,
            height: geometry.notchFrame.height + Layout.hotZoneBottomOverflow
        )
        return TopPanelLayout(
            frame: frame,
            presentation: .collapsed(
                notchWidth: geometry.notchFrame.width,
                extensionWidth: Layout.extensionWidth,
                notchHeight: geometry.notchFrame.height
            )
        )
    }

    private func bridgeTopPanelLayout(using geometry: NotchGeometry, finalPanelFrame: NSRect) -> TopPanelLayout {
        let frame = NSRect(
            x: finalPanelFrame.minX,
            y: geometry.notchFrame.minY - Layout.bridgePanelOverlap,
            width: finalPanelFrame.width,
            height: geometry.notchFrame.height + Layout.bridgePanelOverlap
        )
        return TopPanelLayout(
            frame: frame,
            presentation: .bridge(
                surfaceX: geometry.notchFrame.maxX - finalPanelFrame.minX,
                extensionWidth: Layout.extensionWidth,
                notchHeight: geometry.notchFrame.height,
                visibleHeight: frame.height
            )
        )
    }

    private func expandedPanelFrame(using geometry: NotchGeometry, panelSize: NSSize? = nil) -> NSRect {
        guard let screen = primaryScreen() else { return expandedPanel.frame }
        let size = panelSize ?? expandedPanel.frame.size
        let visibleFrame = screen.visibleFrame

        let proposedX = geometry.notchFrame.midX - size.width / 2
        let x = min(
            max(proposedX, visibleFrame.minX + Layout.screenInset),
            visibleFrame.maxX - size.width - Layout.screenInset
        )
        let y = geometry.notchFrame.maxY - size.height

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func animationSeedFrame(using geometry: NotchGeometry) -> NSRect {
        geometry.notchFrame
    }

    private func updateGeometry() -> NotchGeometry? {
        guard let screen = primaryScreen() else {
            currentGeometry = nil
            return nil
        }
        let geometry = notchGeometry(for: screen)
        currentGeometry = geometry
        return geometry
    }

    private func notchGeometry(for screen: NSScreen) -> NotchGeometry {
        let notchFrame = actualNotchFrame(for: screen) ?? estimatedNotchFrame(for: screen)
        return NotchGeometry(
            notchFrame: notchFrame,
            safeAreaTopInset: max(screen.safeAreaInsets.top, 0)
        )
    }

    private func actualNotchFrame(for screen: NSScreen) -> NSRect? {
        guard #available(macOS 12.0, *),
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return nil
        }

        let notchWidth = rightArea.minX - leftArea.maxX
        guard notchWidth > 0 else { return nil }

        let y = min(leftArea.minY, rightArea.minY)
        let height = min(leftArea.height, rightArea.height)
        return NSRect(x: leftArea.maxX, y: y, width: notchWidth, height: height)
    }

    private func estimatedNotchFrame(for screen: NSScreen) -> NSRect {
        let height = max(screen.safeAreaInsets.top, Layout.estimatedNotchHeight)
        return NSRect(
            x: screen.frame.midX - Layout.estimatedNotchWidth / 2,
            y: screen.frame.maxY - height,
            width: Layout.estimatedNotchWidth,
            height: height
        )
    }

    private func primaryScreen() -> NSScreen? {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return screenNumber?.uint32Value == mainDisplayID
        }
    }

    private static func makePanel(hasShadow: Bool) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = hasShadow
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.worksWhenModal = true
        return panel
    }
}

private final class NotchTrackingContainerView: NSView {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?

    private var trackingAreaToken: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaToken {
            removeTrackingArea(trackingAreaToken)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        trackingAreaToken = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExited?()
    }
}
