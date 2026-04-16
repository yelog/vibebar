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
        var sessions: [SessionSnapshot]
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
        static let expandedPanelWidth: CGFloat = 440
        static let expandedAnimationDuration: TimeInterval = 0.40
        static let collapsedAnimationDuration: TimeInterval = 0.30
        static let fallbackMaximumPanelHeight: CGFloat = 560
    }

    var onExpandedStateChange: ((Bool) -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenSession: ((SessionSnapshot) -> Void)?
    var onQuit: (() -> Void)?

    private let notchPanel: NSPanel
    private let notchContainerView: NotchTrackingContainerView
    private let notchHostingView: NSHostingView<NotchPanelRootView>

    private var hoverStateMachine = NotchHoverStateMachine()
    private var expandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var localMouseMoveMonitor: Any?
    private var globalMouseMoveMonitor: Any?
    private(set) var isExpanded = false
    private var currentGeometry: NotchGeometry?
    private var panelPhase: NotchPanelPhase = .collapsed
    private var collapsedContentSize = NSSize(
        width: Layout.estimatedNotchWidth + (Layout.extensionWidth * 2),
        height: Layout.estimatedNotchHeight + Layout.hotZoneBottomOverflow
    )
    private var expandedContentSize = NSSize(
        width: Layout.expandedPanelWidth,
        height: Layout.estimatedNotchHeight + Layout.bridgePanelOverlap
    )
    private var payload = Payload(
        summary: GlobalSummary(total: 0, counts: [:], byTool: [:], updatedAt: Date()),
        sessions: [],
        model: MonitorViewModel.shared,
        usageSnapshot: nil,
        usageEnabled: false,
        isUsageRefreshing: false
    )

    init() {
        let initialPresentation = NotchCollapsedView.Presentation.collapsed(
            notchWidth: Layout.estimatedNotchWidth,
            extensionWidth: Layout.extensionWidth,
            notchHeight: Layout.estimatedNotchHeight
        )
        let initialLayoutModel = NotchPanelLayoutModel(phase: .collapsed)
        notchHostingView = NSHostingView(
            rootView: NotchPanelRootView(
                summary: payload.summary,
                sessions: payload.sessions,
                model: payload.model,
                usageSnapshot: payload.usageSnapshot,
                usageEnabled: payload.usageEnabled,
                isUsageRefreshing: payload.isUsageRefreshing,
                contentTopInset: 0,
                panelWidth: collapsedContentSize.width,
                panelHeight: collapsedContentSize.height,
                topShellPresentation: initialPresentation,
                layoutModel: initialLayoutModel,
                onRefresh: {},
                onOpenSettings: {},
                onOpenSession: { _ in },
                onQuit: {}
            )
        )

        notchContainerView = NotchTrackingContainerView()
        notchPanel = Self.makePanel(hasShadow: false)

        installContent()
        applyForcedAppearance()
        configureTracking()
    }

    func show(payload: Payload) {
        self.payload = payload
        installPointerMonitorsIfNeeded()
        guard let geometry = updateGeometry() else { return }
        panelPhase = .collapsed
        hoverStateMachine = NotchHoverStateMachine(state: .collapsed)
        refreshContent(using: geometry)
        notchPanel.setFrame(collapsedTopPanelLayout(using: geometry).frame, display: true)
        notchPanel.alphaValue = 1
        notchPanel.orderFrontRegardless()
    }

    func update(payload: Payload) {
        self.payload = payload
        guard let geometry = updateGeometry() else { return }
        refreshContent(using: geometry)
        guard notchPanel.isVisible else { return }

        switch panelPhase {
        case .collapsed:
            notchPanel.setFrame(collapsedTopPanelLayout(using: geometry).frame, display: false)
        case .expanded:
            notchPanel.setFrame(expandedPanelFrame(using: geometry, panelSize: expandedContentSize), display: false)
        case .expanding, .collapsing:
            break
        }
    }

    func hide() {
        cancelTimers()
        removePointerMonitors()
        hoverStateMachine = NotchHoverStateMachine()
        panelPhase = .collapsed
        if isExpanded {
            isExpanded = false
            onExpandedStateChange?(false)
        }
        notchPanel.orderOut(nil)
    }

    func expandFromNotification(payload: Payload) {
        show(payload: payload)
        cancelTimers()
        expandImmediately()
    }

    func collapse() {
        guard isExpanded else { return }
        collapseImmediately()
    }

    private func installContent() {
        notchContainerView.wantsLayer = true
        notchContainerView.addSubview(notchHostingView)
        notchPanel.contentView = notchContainerView
    }

    private func applyForcedAppearance() {
        guard let appearance = Self.forcedAppearance else { return }
        notchPanel.appearance = appearance
        notchContainerView.appearance = appearance
        notchHostingView.appearance = appearance
    }

    private func configureTracking() {
        notchContainerView.onPointerEntered = { [weak self] in
            self?.reconcilePointerPresence()
        }
        notchContainerView.onPointerExited = { [weak self] in
            self?.reconcilePointerPresence()
        }
        notchContainerView.onLayout = { [weak self] in
            self?.layoutHostingView()
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
        guard notchPanel.isVisible else { return false }
        let mouseLocation = NSEvent.mouseLocation
        let layoutModel = NotchPanelLayoutModel(phase: panelPhase)

        if layoutModel.usesExpandedHitFrame,
           let geometry = currentGeometry ?? updateGeometry() {
            let expandedFrame = expandedPanelFrame(using: geometry, panelSize: expandedContentSize)
            if expandedHitFrame(for: expandedFrame).contains(mouseLocation) {
                return true
            }
        }

        return expandedHitFrame(for: notchPanel.frame).contains(mouseLocation)
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
        panelPhase = .expanding
        hoverStateMachine = NotchHoverStateMachine(state: .expanded)
        refreshContent(using: geometry)

        let collapsedFrame = collapsedTopPanelLayout(using: geometry).frame
        let finalFrame = expandedPanelFrame(using: geometry, panelSize: expandedContentSize)

        notchPanel.setFrame(collapsedFrame, display: true)
        notchPanel.alphaValue = 1
        notchPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.expandedAnimationDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1)
            context.allowsImplicitAnimation = true
            notchPanel.animator().setFrame(finalFrame, display: true)
        } completionHandler: {
            Task { @MainActor in
                self.panelPhase = .expanded
                self.refreshContent(using: geometry)
                self.notchPanel.setFrame(
                    self.expandedPanelFrame(using: geometry, panelSize: self.expandedContentSize),
                    display: false
                )
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
        panelPhase = .collapsing
        hoverStateMachine = NotchHoverStateMachine(state: .collapsed)
        refreshContent(using: geometry)

        let finalFrame = collapsedTopPanelLayout(using: geometry).frame

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.collapsedAnimationDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.15, 1.0)
            context.allowsImplicitAnimation = true
            notchPanel.animator().setFrame(finalFrame, display: true)
        } completionHandler: {
            Task { @MainActor in
                self.panelPhase = .collapsed
                self.refreshContent(using: geometry)
                self.notchPanel.setFrame(finalFrame, display: false)
                self.reconcilePointerPresence()
            }
        }

        if isExpanded {
            isExpanded = false
            onExpandedStateChange?(false)
        }
    }

    private func refreshContent(using geometry: NotchGeometry? = nil) {
        guard let geometry = geometry ?? currentGeometry ?? updateGeometry() else { return }
        expandedContentSize = measureExpandedContentSize(using: geometry)

        let collapsedFrame = collapsedTopPanelLayout(using: geometry).frame
        let expandedFrame = expandedPanelFrame(using: geometry, panelSize: expandedContentSize)
        let layoutModel = NotchPanelLayoutModel(
            phase: panelPhase,
            collapsedFrame: collapsedFrame,
            expandedFrame: expandedFrame
        )
        collapsedContentSize = collapsedFrame.size
        let presentation = topShellPresentation(using: geometry, expandedFrame: expandedFrame)
        let contentTopInset = panelPhase == .collapsed ? 0 : expandedContentTopInset(using: geometry)

        notchHostingView.rootView = NotchPanelRootView(
            summary: payload.summary,
            sessions: payload.sessions,
            model: payload.model,
            usageSnapshot: payload.usageSnapshot,
            usageEnabled: payload.usageEnabled,
            isUsageRefreshing: payload.isUsageRefreshing,
            contentTopInset: contentTopInset,
            panelWidth: layoutModel.hostingSize.width,
            panelHeight: layoutModel.hostingSize.height,
            topShellPresentation: presentation,
            layoutModel: layoutModel,
            onRefresh: { [weak self] in self?.onRefresh?() },
            onOpenSettings: { [weak self] in self?.onOpenSettings?() },
            onOpenSession: { [weak self] session in self?.onOpenSession?(session) },
            onQuit: { [weak self] in self?.onQuit?() }
        )
        layoutHostingView()
    }

    private func layoutHostingView() {
        let hostingSize: NSSize
        if let geometry = currentGeometry {
            let collapsedFrame = collapsedTopPanelLayout(using: geometry).frame
            let expandedFrame = expandedPanelFrame(using: geometry, panelSize: expandedContentSize)
            hostingSize = NotchPanelLayoutModel(
                phase: panelPhase,
                collapsedFrame: collapsedFrame,
                expandedFrame: expandedFrame
            ).hostingSize
        } else {
            hostingSize = panelPhase == .collapsed ? collapsedContentSize : expandedContentSize
        }

        guard notchContainerView.bounds.width > 0, notchContainerView.bounds.height > 0 else {
            notchHostingView.frame = NSRect(origin: .zero, size: hostingSize)
            return
        }

        let originX: CGFloat
        if let geometry = currentGeometry {
            switch panelPhase {
            case .expanded, .expanding:
                let expandedFrame = expandedPanelFrame(using: geometry, panelSize: expandedContentSize)
                originX = expandedFrame.minX - notchPanel.frame.minX
            case .collapsing:
                let collapsedFrame = collapsedTopPanelLayout(using: geometry).frame
                originX = collapsedFrame.minX - notchPanel.frame.minX
            case .collapsed:
                originX = 0
            }
        } else {
            originX = 0
        }

        let originY = notchContainerView.bounds.height - hostingSize.height
        notchHostingView.frame = NSRect(
            x: originX,
            y: originY,
            width: hostingSize.width,
            height: hostingSize.height
        )
    }

    private func measureExpandedContentSize(using geometry: NotchGeometry) -> NSSize {
        let measureWidth = Layout.expandedPanelWidth
        let provisionalFrame = expandedPanelFrame(
            using: geometry,
            panelSize: NSSize(width: measureWidth, height: 1)
        )
        let measuringView = NSHostingView(
            rootView: NotchPanelRootView(
                summary: payload.summary,
                sessions: payload.sessions,
                model: payload.model,
                usageSnapshot: payload.usageSnapshot,
                usageEnabled: payload.usageEnabled,
                isUsageRefreshing: payload.isUsageRefreshing,
                contentTopInset: expandedContentTopInset(using: geometry),
                panelWidth: measureWidth,
                panelHeight: nil,
                topShellPresentation: bridgeTopPanelLayout(using: geometry, finalPanelFrame: provisionalFrame).presentation,
                layoutModel: NotchPanelLayoutModel(phase: .expanded),
                onRefresh: {},
                onOpenSettings: {},
                onOpenSession: { _ in },
                onQuit: {}
            )
        )
        measuringView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: measureWidth, height: maximumExpandedPanelHeight(using: geometry))
        )
        measuringView.layoutSubtreeIfNeeded()

        let fittingSize = measuringView.fittingSize
        return NSSize(
            width: max(fittingSize.width, measureWidth),
            height: min(fittingSize.height, maximumExpandedPanelHeight(using: geometry))
        )
    }

    private func expandedContentTopInset(using geometry: NotchGeometry) -> CGFloat {
        max(geometry.notchFrame.height, geometry.safeAreaTopInset, Layout.bridgePanelOverlap)
    }

    private func topShellPresentation(using geometry: NotchGeometry, expandedFrame: NSRect) -> NotchCollapsedView.Presentation {
        switch panelPhase {
        case .expanded, .expanding:
            bridgeTopPanelLayout(using: geometry, finalPanelFrame: expandedFrame).presentation
        case .collapsed, .collapsing:
            collapsedTopPanelLayout(using: geometry).presentation
        }
    }

    private func collapsedTopPanelLayout(using geometry: NotchGeometry) -> TopPanelLayout {
        let frame = NSRect(
            x: geometry.notchFrame.minX - Layout.extensionWidth,
            y: geometry.notchFrame.minY - Layout.hotZoneBottomOverflow,
            width: geometry.notchFrame.width + (Layout.extensionWidth * 2),
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
                notchWidth: geometry.notchFrame.width,
                extensionWidth: Layout.extensionWidth,
                notchHeight: geometry.notchFrame.height,
                visibleHeight: frame.height
            )
        )
    }

    private func expandedPanelFrame(using geometry: NotchGeometry, panelSize: NSSize? = nil) -> NSRect {
        guard let screen = primaryScreen() else { return notchPanel.frame }
        let size = panelSize ?? expandedContentSize
        let visibleFrame = screen.visibleFrame

        let proposedX = geometry.notchFrame.midX - size.width / 2
        let x = min(
            max(proposedX, visibleFrame.minX + Layout.screenInset),
            visibleFrame.maxX - size.width - Layout.screenInset
        )
        let y = geometry.notchFrame.maxY - size.height

        return NSRect(x: x, y: y, width: size.width, height: size.height)
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

    private func maximumExpandedPanelHeight(using geometry: NotchGeometry) -> CGFloat {
        guard let screen = primaryScreen() else {
            return Layout.fallbackMaximumPanelHeight
        }

        let availableHeight = geometry.notchFrame.maxY - screen.visibleFrame.minY - Layout.screenInset
        return max(availableHeight, 240)
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
    var onLayout: (() -> Void)?
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

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExited?()
    }
}
