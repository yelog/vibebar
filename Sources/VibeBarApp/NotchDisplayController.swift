import AppKit
import SwiftUI
import VibeBarCore

@MainActor
final class NotchDisplayController {
    private struct NotchGeometry {
        var notchFrame: NSRect
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
        static let collapsedAnimationDuration: TimeInterval = 0.18
        static let expandedAnimationDuration: TimeInterval = 0.28
        static let maximumPanelHeight: CGFloat = 560
        static let animationSeedWidth: CGFloat = 44
        static let animationSeedHeight: CGFloat = 18
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
                model: payload.model,
                usageSnapshot: payload.usageSnapshot,
                usageEnabled: payload.usageEnabled,
                isUsageRefreshing: payload.isUsageRefreshing,
                topPlaceholderHeight: Layout.estimatedNotchHeight,
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
        configureTracking()
    }

    func show(payload: Payload) {
        self.payload = payload
        refreshContent()
        positionCollapsedPanel()
        collapsedPanel.alphaValue = 1
        collapsedPanel.orderFrontRegardless()
    }

    func update(payload: Payload) {
        self.payload = payload
        refreshContent()
        guard let geometry = updateGeometry() else { return }

        if expandedPanel.isVisible || isExpanded {
            let finalFrame = expandedPanelFrame(using: geometry)
            applyTopPanelLayout(bridgeTopPanelLayout(using: geometry, finalPanelFrame: finalFrame))
            if expandedPanel.isVisible {
                expandedPanel.setFrame(finalFrame, display: false)
            }
        } else if collapsedPanel.isVisible {
            applyTopPanelLayout(collapsedTopPanelLayout(using: geometry))
        }
    }

    func hide() {
        cancelTimers()
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

    private func configureTracking() {
        collapsedContainerView.onPointerEntered = { [weak self] in
            self?.handleHoverEvent(.pointerEnteredHotZone)
        }
        collapsedContainerView.onPointerExited = { [weak self] in
            self?.handleHoverEvent(.pointerExitedAllZones)
        }
        expandedContainerView.onPointerEntered = { [weak self] in
            self?.handleHoverEvent(.pointerEnteredHotZone)
        }
        expandedContainerView.onPointerExited = { [weak self] in
            self?.handleHoverEvent(.pointerExitedAllZones)
        }
    }

    private func handleHoverEvent(_ event: NotchHoverStateMachine.Event) {
        let effect = hoverStateMachine.reduce(event)
        apply(effect: effect)
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
        let startFrame = animationSeedFrame(using: geometry, finalFrame: finalFrame)
        let seedTopPanelLayout = bridgeSeedTopPanelLayout(using: geometry)
        let finalTopPanelLayout = bridgeTopPanelLayout(using: geometry, finalPanelFrame: finalFrame)

        applyTopPanelLayout(
            TopPanelLayout(frame: seedTopPanelLayout.frame, presentation: finalTopPanelLayout.presentation)
        )
        expandedPanel.setFrame(startFrame, display: true)
        expandedPanel.alphaValue = 0
        expandedPanel.orderFrontRegardless()
        collapsedPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.expandedAnimationDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            context.allowsImplicitAnimation = true
            collapsedPanel.animator().setFrame(finalTopPanelLayout.frame, display: true)
            expandedPanel.animator().setFrame(finalFrame, display: true)
            expandedPanel.animator().alphaValue = 1
        }

        if !isExpanded {
            isExpanded = true
            onExpandedStateChange?(true)
        }
    }

    private func collapseImmediately() {
        guard let geometry = updateGeometry() else { return }
        cancelTimers()
        let expandedFrame = expandedPanelFrame(using: geometry)
        let finalFrame = animationSeedFrame(using: geometry, finalFrame: expandedFrame)
        let finalTopPanelLayout = bridgeSeedTopPanelLayout(using: geometry)

        applyTopPanelLayout(bridgeTopPanelLayout(using: geometry, finalPanelFrame: expandedFrame))
        collapsedPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.collapsedAnimationDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            context.allowsImplicitAnimation = true
            collapsedPanel.animator().setFrame(finalTopPanelLayout.frame, display: true)
            expandedPanel.animator().setFrame(finalFrame, display: true)
            expandedPanel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                self.applyTopPanelLayout(self.collapsedTopPanelLayout(using: geometry))
                self.expandedPanel.orderOut(nil)
                self.expandedPanel.alphaValue = 1
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
            model: payload.model,
            usageSnapshot: payload.usageSnapshot,
            usageEnabled: payload.usageEnabled,
            isUsageRefreshing: payload.isUsageRefreshing,
            topPlaceholderHeight: expandedContentTopPlaceholderHeight(),
            onRefresh: { [weak self] in self?.onRefresh?() },
            onOpenSettings: { [weak self] in self?.onOpenSettings?() },
            onQuit: { [weak self] in self?.onQuit?() }
        )
        refreshExpandedPanelLayout()
    }

    private func refreshExpandedPanelLayout() {
        expandedHostingView.layoutSubtreeIfNeeded()
        let fittingSize = expandedHostingView.fittingSize
        let size = NSSize(
            width: max(fittingSize.width, 440),
            height: min(fittingSize.height, Layout.maximumPanelHeight)
        )
        expandedContainerView.frame = NSRect(origin: .zero, size: size)
        expandedHostingView.frame = NSRect(origin: .zero, size: size)
        expandedPanel.setContentSize(size)
    }

    private func expandedContentTopPlaceholderHeight() -> CGFloat {
        let notchHeight = currentGeometry?.notchFrame.height ?? Layout.estimatedNotchHeight
        return max(notchHeight, Layout.bridgePanelOverlap)
    }

    private func positionCollapsedPanel() {
        guard let geometry = updateGeometry() else { return }
        applyTopPanelLayout(collapsedTopPanelLayout(using: geometry))
    }

    private func positionExpandedPanel(animated: Bool) {
        guard let geometry = updateGeometry() else { return }
        let frame = expandedPanelFrame(using: geometry)
        if animated {
            expandedPanel.animator().setFrame(frame, display: true)
        } else {
            expandedPanel.setFrame(frame, display: false)
        }
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

    private func bridgeSeedTopPanelLayout(using geometry: NotchGeometry) -> TopPanelLayout {
        let frame = NSRect(
            x: geometry.notchFrame.midX - Layout.animationSeedWidth / 2,
            y: geometry.notchFrame.minY - Layout.bridgePanelOverlap,
            width: Layout.animationSeedWidth,
            height: geometry.notchFrame.height + Layout.bridgePanelOverlap
        )
        return TopPanelLayout(
            frame: frame,
            presentation: .bridge(
                surfaceX: geometry.notchFrame.maxX - frame.minX,
                extensionWidth: Layout.extensionWidth,
                notchHeight: geometry.notchFrame.height,
                visibleHeight: frame.height
            )
        )
    }

    private func expandedPanelFrame(using geometry: NotchGeometry) -> NSRect {
        guard let screen = primaryScreen() else { return expandedPanel.frame }
        let size = expandedPanel.frame.size
        let visibleFrame = screen.visibleFrame

        let proposedX = geometry.notchFrame.midX - size.width / 2
        let x = min(
            max(proposedX, visibleFrame.minX + Layout.screenInset),
            visibleFrame.maxX - size.width - Layout.screenInset
        )
        let y = geometry.notchFrame.minY - size.height

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func animationSeedFrame(using geometry: NotchGeometry, finalFrame: NSRect) -> NSRect {
        let width = Layout.animationSeedWidth
        let height = Layout.animationSeedHeight
        let maxY = finalFrame.maxY
        return NSRect(
            x: geometry.notchFrame.midX - width / 2,
            y: maxY - height,
            width: width,
            height: height
        )
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
        return NotchGeometry(notchFrame: notchFrame)
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
