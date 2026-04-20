import AppKit
import SwiftUI
import VibeBarCore

struct NotchAutoExpandHoldWindow {
    let duration: TimeInterval
    private(set) var holdUntil: Date?

    init(duration: TimeInterval) {
        self.duration = duration
    }

    @discardableResult
    mutating func begin(now: Date = Date()) -> Date {
        let holdUntil = now.addingTimeInterval(duration)
        self.holdUntil = holdUntil
        return holdUntil
    }

    mutating func clear() {
        holdUntil = nil
    }

    @discardableResult
    mutating func refresh(now: Date = Date()) -> Date {
        let holdUntil = now.addingTimeInterval(duration)
        self.holdUntil = holdUntil
        return holdUntil
    }

    func isActive(now: Date = Date()) -> Bool {
        guard let holdUntil else { return false }
        return now < holdUntil
    }
}

struct NotchAutoExpandFocusState {
    private(set) var focusedSessionID: String?

    mutating func begin(sessionID: String) {
        focusedSessionID = sessionID
    }

    @discardableResult
    mutating func revealFullPanel() -> Bool {
        guard focusedSessionID != nil else { return false }
        focusedSessionID = nil
        return true
    }

    mutating func clear() {
        focusedSessionID = nil
    }
}

enum NotchAutoExpandPointerDecision: Equatable {
    case revealFullPanel
    case extendFocusedWindow
    case pointerInsideVisiblePanel
    case outside

    static func resolve(
        isFocusedAutoExpandActive: Bool,
        pointerInRevealZone: Bool,
        pointerInFocusedBodyZone: Bool,
        pointerInVisiblePanel: Bool
    ) -> Self {
        if isFocusedAutoExpandActive {
            if pointerInRevealZone {
                return .revealFullPanel
            }
            if pointerInFocusedBodyZone {
                return .extendFocusedWindow
            }
        }

        return pointerInVisiblePanel ? .pointerInsideVisiblePanel : .outside
    }
}

@MainActor
final class NotchDisplayController {
    private static let forcedAppearance = NSAppearance(named: .darkAqua)

    private struct NotchGeometry {
        var notchFrame: NSRect
        var safeAreaTopInset: CGFloat
    }

    private struct TopPanelLayout {
        var frame: NSRect
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
        static let expandedAnimationDuration: TimeInterval = 0.42
        static let collapsedAnimationDuration: TimeInterval = 0.38
        static let fallbackMaximumPanelHeight: CGFloat = 560
        static let stateChangeAutoExpandHoldDuration: TimeInterval = 3
    }

    var onExpandedStateChange: ((Bool) -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenSession: ((SessionSnapshot) -> Void)?
    var onQuit: (() -> Void)?

    private let notchPanel: NSPanel
    private let notchContainerView: NotchTrackingContainerView
    private let notchViewState: NotchPanelViewState
    private let notchHostingView: NotchHostingView<NotchPanelRootView>

    private var hoverStateMachine = NotchHoverStateMachine()
    private var autoExpandFocusState = NotchAutoExpandFocusState()
    private var autoExpandHoldWindow = NotchAutoExpandHoldWindow(
        duration: Layout.stateChangeAutoExpandHoldDuration
    )
    private var autoExpandHoldWorkItem: DispatchWorkItem?
    private var expandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var localMouseMoveMonitor: Any?
    private var globalMouseMoveMonitor: Any?
    private(set) var isExpanded = false
    private var currentGeometry: NotchGeometry?
    private var panelPhase: NotchPanelPhase = .collapsed
    private var needsRefreshAfterTransition = false
    private var hasMeasuredExpandedContentSize = false
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
        notchViewState = NotchPanelViewState(
            summary: payload.summary,
            sessions: payload.sessions,
            model: payload.model,
            usageSnapshot: payload.usageSnapshot,
            usageEnabled: payload.usageEnabled,
            isUsageRefreshing: payload.isUsageRefreshing,
            focusedSessionID: autoExpandFocusState.focusedSessionID,
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
        notchHostingView = NotchHostingView(
            rootView: NotchPanelRootView(state: notchViewState)
        )

        notchContainerView = NotchTrackingContainerView()
        notchPanel = Self.makePanel(hasShadow: false)

        installContent()
        applyForcedAppearance()
        configureTracking()
    }

    func show(payload: Payload) {
        self.payload = payload
        autoExpandFocusState.clear()
        clearAutoExpandHold()
        needsRefreshAfterTransition = false
        installPointerMonitorsIfNeeded()
        guard let geometry = updateGeometry() else { return }
        panelPhase = .collapsed
        hoverStateMachine = NotchHoverStateMachine(state: .collapsed)
        refreshContent(using: geometry, allowRemeasure: !hasMeasuredExpandedContentSize, animated: false)
        notchPanel.setFrame(collapsedTopPanelLayout(using: geometry).frame, display: true)
        notchPanel.alphaValue = 1
        notchPanel.orderFrontRegardless()
    }

    func update(payload: Payload) {
        self.payload = payload
        guard let geometry = updateGeometry() else { return }

        if panelPhase.isTransitioning {
            needsRefreshAfterTransition = true
            return
        }

        refreshContent(using: geometry, animated: false)
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
        autoExpandFocusState.clear()
        clearAutoExpandHold()
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

    func expandForStateChange(payload: Payload, focusedSessionID: String) {
        guard !isExpanded, !panelPhase.isTransitioning else { return }
        show(payload: payload)
        autoExpandFocusState.begin(sessionID: focusedSessionID)
        startAutoExpandHold()
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
        let pointerInVisiblePanel = isPointerInsideVisiblePanel()
        let decision = NotchAutoExpandPointerDecision.resolve(
            isFocusedAutoExpandActive: autoExpandFocusState.focusedSessionID != nil,
            pointerInRevealZone: isPointerInsideRevealZone(),
            pointerInFocusedBodyZone: isPointerInsideFocusedBodyZone(),
            pointerInVisiblePanel: pointerInVisiblePanel
        )

        switch decision {
        case .revealFullPanel:
            revealFullPanelIfNeeded()

            if autoExpandHoldWindow.isActive() {
                clearAutoExpandHold()
            }
            handleHoverEvent(.pointerEnteredHotZone)
        case .extendFocusedWindow:
            refreshAutoExpandHold()
        case .pointerInsideVisiblePanel:
            if autoExpandHoldWindow.isActive() {
                clearAutoExpandHold()
            }
            handleHoverEvent(.pointerEnteredHotZone)
        case .outside:
            guard !autoExpandHoldWindow.isActive() else {
                return
            }

            handleHoverEvent(.pointerExitedAllZones)
        }
    }

    private func revealFullPanelIfNeeded() {
        guard autoExpandFocusState.revealFullPanel() else { return }
        clearAutoExpandHold()

        guard panelPhase == .expanded,
              let geometry = currentGeometry ?? updateGeometry() else { return }

        refreshContent(using: geometry, allowRemeasure: true, animated: true)
        notchPanel.setFrame(
            expandedPanelFrame(using: geometry, panelSize: expandedContentSize),
            display: true,
            animate: true
        )
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

    private func isPointerInsideRevealZone() -> Bool {
        guard notchPanel.isVisible,
              let geometry = currentGeometry ?? updateGeometry() else { return false }

        let mouseLocation = NSEvent.mouseLocation
        let revealFrame = expandedHitFrame(for: collapsedTopPanelLayout(using: geometry).frame)
        return revealFrame.contains(mouseLocation)
    }

    private func isPointerInsideFocusedBodyZone() -> Bool {
        guard notchPanel.isVisible,
              autoExpandFocusState.focusedSessionID != nil else { return false }

        let mouseLocation = NSEvent.mouseLocation
        let visibleFrame = expandedHitFrame(for: notchPanel.frame)
        guard visibleFrame.contains(mouseLocation) else { return false }
        return !isPointerInsideRevealZone()
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

    private func startAutoExpandHold(now: Date = Date()) {
        clearAutoExpandHold()

        let holdUntil = autoExpandHoldWindow.begin(now: now)
        scheduleAutoExpandHoldExpiration(holdUntil: holdUntil, now: now)
    }

    private func refreshAutoExpandHold(now: Date = Date()) {
        let holdUntil = autoExpandHoldWindow.refresh(now: now)
        scheduleAutoExpandHoldExpiration(holdUntil: holdUntil, now: now)
    }

    private func scheduleAutoExpandHoldExpiration(holdUntil: Date, now: Date) {
        autoExpandHoldWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.autoExpandHoldWorkItem = nil
            self.autoExpandHoldWindow.clear()
            self.reconcilePointerPresence()
        }
        autoExpandHoldWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, holdUntil.timeIntervalSince(now)),
            execute: workItem
        )
    }

    private func clearAutoExpandHold() {
        autoExpandHoldWorkItem?.cancel()
        autoExpandHoldWorkItem = nil
        autoExpandHoldWindow.clear()
    }

    private func expandImmediately() {
        guard let geometry = updateGeometry() else { return }
        cancelTimers()
        panelPhase = .expanding
        needsRefreshAfterTransition = false
        hoverStateMachine = NotchHoverStateMachine(state: .expanded)
        expandedContentSize = measureExpandedContentSize(using: geometry)
        hasMeasuredExpandedContentSize = true

        let collapsedFrame = collapsedTopPanelLayout(using: geometry).frame
        let finalFrame = expandedPanelFrame(using: geometry, panelSize: expandedContentSize)

        notchPanel.setFrame(collapsedFrame, display: true)
        notchPanel.alphaValue = 1
        notchPanel.orderFrontRegardless()
        refreshContent(using: geometry, allowRemeasure: false, animated: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.expandedAnimationDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1)
            context.allowsImplicitAnimation = true
            notchPanel.animator().setFrame(finalFrame, display: true)
        } completionHandler: {
            Task { @MainActor in
                self.needsRefreshAfterTransition = false
                self.panelPhase = .expanded
                self.refreshContent(using: geometry, allowRemeasure: true, animated: false)
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
        clearAutoExpandHold()
        panelPhase = .collapsing
        needsRefreshAfterTransition = false
        hoverStateMachine = NotchHoverStateMachine(state: .collapsed)
        refreshContent(using: geometry, allowRemeasure: false, animated: true)

        let finalFrame = collapsedTopPanelLayout(using: geometry).frame

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.collapsedAnimationDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.15, 1.0)
            context.allowsImplicitAnimation = true
            notchPanel.animator().setFrame(finalFrame, display: true)
        } completionHandler: {
            Task { @MainActor in
                self.needsRefreshAfterTransition = false
                if self.panelPhase != .collapsed {
                    self.panelPhase = .collapsed
                    self.refreshContent(using: geometry, allowRemeasure: false, animated: false)
                }
                self.autoExpandFocusState.clear()
                self.notchPanel.setFrame(finalFrame, display: false)
                self.reconcilePointerPresence()
            }
        }

        if isExpanded {
            isExpanded = false
            onExpandedStateChange?(false)
        }
    }

    private func refreshContent(
        using geometry: NotchGeometry? = nil,
        allowRemeasure: Bool? = nil,
        animated: Bool = false
    ) {
        guard let geometry = geometry ?? currentGeometry ?? updateGeometry() else { return }
        let shouldRemeasure = allowRemeasure ?? !panelPhase.isTransitioning
        if shouldRemeasure && (panelPhase != .collapsed || !hasMeasuredExpandedContentSize) {
            expandedContentSize = measureExpandedContentSize(using: geometry)
            hasMeasuredExpandedContentSize = true
        }

        let collapsedFrame = collapsedTopPanelLayout(using: geometry).frame
        let expandedFrame = expandedPanelFrame(using: geometry, panelSize: expandedContentSize)
        let layoutModel = NotchPanelLayoutModel(
            phase: panelPhase,
            collapsedFrame: collapsedFrame,
            expandedFrame: expandedFrame
        )
        collapsedContentSize = collapsedFrame.size
        let presentation = topShellPresentation(using: geometry, layoutModel: layoutModel)
        let contentTopInset = panelPhase == .collapsed ? 0 : expandedContentTopInset(using: geometry)

        let updateViewState = {
            self.notchViewState.update(
                summary: self.payload.summary,
                sessions: self.payload.sessions,
                model: self.payload.model,
                usageSnapshot: self.payload.usageSnapshot,
                usageEnabled: self.payload.usageEnabled,
                isUsageRefreshing: self.payload.isUsageRefreshing,
                focusedSessionID: self.autoExpandFocusState.focusedSessionID,
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
            self.layoutHostingView()
        }

        if animated {
            withAnimation(animation(for: panelPhase)) {
                updateViewState()
            }
        } else {
            updateViewState()
        }
    }

    private func layoutHostingView() {
        let layoutModel: NotchPanelLayoutModel?
        let geometry: NotchGeometry?
        let hostingSize: NSSize
        if let currentGeometry {
            let collapsedFrame = collapsedTopPanelLayout(using: currentGeometry).frame
            let expandedFrame = expandedPanelFrame(using: currentGeometry, panelSize: expandedContentSize)
            let currentLayoutModel = NotchPanelLayoutModel(
                phase: panelPhase,
                collapsedFrame: collapsedFrame,
                expandedFrame: expandedFrame
            )
            layoutModel = currentLayoutModel
            geometry = currentGeometry
            hostingSize = currentLayoutModel.hostingSize
        } else {
            layoutModel = nil
            geometry = nil
            hostingSize = panelPhase == .collapsed ? collapsedContentSize : expandedContentSize
        }

        guard notchContainerView.bounds.width > 0, notchContainerView.bounds.height > 0 else {
            notchHostingView.frame = NSRect(origin: .zero, size: hostingSize)
            return
        }

        let originX: CGFloat
        if let layoutModel {
            originX = layoutModel.hostingReferenceFrame.minX - notchPanel.frame.minX
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

        if let geometry, let layoutModel {
            synchronizeTopShellPresentation(using: geometry, layoutModel: layoutModel)
        }
    }

    private func measureExpandedContentSize(using geometry: NotchGeometry) -> NSSize {
        let measureWidth = Layout.expandedPanelWidth
        let provisionalFrame = expandedPanelFrame(
            using: geometry,
            panelSize: NSSize(width: measureWidth, height: 1)
        )
        let measuringLayoutModel = NotchPanelLayoutModel(
            phase: .expanded,
            collapsedFrame: collapsedTopPanelLayout(using: geometry).frame,
            expandedFrame: provisionalFrame
        )
        let measuringState = NotchPanelViewState(
            summary: payload.summary,
            sessions: payload.sessions,
            model: payload.model,
            usageSnapshot: payload.usageSnapshot,
            usageEnabled: payload.usageEnabled,
            isUsageRefreshing: payload.isUsageRefreshing,
            focusedSessionID: autoExpandFocusState.focusedSessionID,
            contentTopInset: expandedContentTopInset(using: geometry),
            panelWidth: measureWidth,
            panelHeight: nil,
            topShellPresentation: topShellPresentation(
                using: geometry,
                layoutModel: measuringLayoutModel,
                currentPanelFrame: provisionalFrame
            ),
            layoutModel: measuringLayoutModel,
            onRefresh: {},
            onOpenSettings: {},
            onOpenSession: { _ in },
            onQuit: {}
        )
        let measuringView = NSHostingView(
            rootView: NotchPanelRootView(state: measuringState)
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

    private func animation(for phase: NotchPanelPhase) -> Animation {
        switch phase {
        case .collapsed, .collapsing:
            NotchAnimation.close
        case .expanded, .expanding:
            NotchAnimation.open
        }
    }

    private func expandedContentTopInset(using geometry: NotchGeometry) -> CGFloat {
        max(geometry.notchFrame.height, geometry.safeAreaTopInset, Layout.bridgePanelOverlap)
    }

    private func topShellPresentation(
        using geometry: NotchGeometry,
        layoutModel: NotchPanelLayoutModel,
        currentPanelFrame: NSRect? = nil
    ) -> NotchCollapsedView.Presentation {
        let referenceFrame = layoutModel.hostingReferenceFrame
        let panelFrame = resolvedTopShellPanelFrame(layoutModel: layoutModel, currentPanelFrame: currentPanelFrame)
        let progress = topShellProgress(
            currentWidth: panelFrame.width,
            collapsedWidth: layoutModel.collapsedFrame.width,
            expandedWidth: layoutModel.expandedFrame.width
        )
        let collapsedLeftIconX = layoutModel.collapsedFrame.minX - referenceFrame.minX
        let collapsedRightIconX = collapsedLeftIconX + layoutModel.collapsedFrame.width - Layout.extensionWidth
        let expandedLeftIconX = geometry.notchFrame.minX - referenceFrame.minX - Layout.extensionWidth
        let expandedRightIconX = geometry.notchFrame.maxX - referenceFrame.minX

        return NotchCollapsedView.Presentation(
            surfaceX: panelFrame.minX - referenceFrame.minX,
            surfaceWidth: panelFrame.width,
            iconWidth: Layout.extensionWidth,
            leftIconX: interpolate(collapsedLeftIconX, expandedLeftIconX, progress: progress),
            rightIconX: interpolate(collapsedRightIconX, expandedRightIconX, progress: progress),
            notchHeight: geometry.notchFrame.height,
            visibleHeight: interpolate(
                geometry.notchFrame.height,
                geometry.notchFrame.height + Layout.bridgePanelOverlap,
                progress: progress
            ),
            bottomCornerRadius: interpolate(NotchPanelStyle.cornerRadius, 0, progress: progress)
        )
    }

    private func resolvedTopShellPanelFrame(
        layoutModel: NotchPanelLayoutModel,
        currentPanelFrame: NSRect?
    ) -> NSRect {
        if let currentPanelFrame, currentPanelFrame.width > 0 {
            return currentPanelFrame
        }

        switch layoutModel.phase {
        case .collapsed, .expanding:
            return layoutModel.collapsedFrame
        case .expanded, .collapsing:
            return layoutModel.expandedFrame
        }
    }

    private func topShellProgress(
        currentWidth: CGFloat,
        collapsedWidth: CGFloat,
        expandedWidth: CGFloat
    ) -> CGFloat {
        let deltaWidth = max(expandedWidth - collapsedWidth, 1)
        let rawProgress = (currentWidth - collapsedWidth) / deltaWidth
        return min(max(rawProgress, 0), 1)
    }

    private func synchronizeTopShellPresentation(
        using geometry: NotchGeometry,
        layoutModel: NotchPanelLayoutModel
    ) {
        guard layoutModel.phase.isTransitioning else { return }
        let presentation = topShellPresentation(
            using: geometry,
            layoutModel: layoutModel,
            currentPanelFrame: notchPanel.frame
        )
        notchViewState.updateTopShellPresentation(presentation)
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, progress: CGFloat) -> CGFloat {
        start + ((end - start) * progress)
    }

    private func collapsedTopPanelLayout(using geometry: NotchGeometry) -> TopPanelLayout {
        TopPanelLayout(
            frame: NSRect(
                x: geometry.notchFrame.minX - Layout.extensionWidth,
                y: geometry.notchFrame.minY - Layout.hotZoneBottomOverflow,
                width: geometry.notchFrame.width + (Layout.extensionWidth * 2),
                height: geometry.notchFrame.height + Layout.hotZoneBottomOverflow
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

private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    private var applyingDeferred = false

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var needsUpdateConstraints: Bool {
        get { super.needsUpdateConstraints }
        set {
            if applyingDeferred {
                super.needsUpdateConstraints = newValue
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.applySuperNeedsUpdateConstraints(newValue)
            }
        }
    }

    private func applySuperNeedsUpdateConstraints(_ value: Bool) {
        applyingDeferred = true
        super.needsUpdateConstraints = value
        applyingDeferred = false
    }

    override var needsLayout: Bool {
        get { super.needsLayout }
        set {
            if applyingDeferred {
                super.needsLayout = newValue
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.applySuperNeedsLayout(newValue)
            }
        }
    }

    private func applySuperNeedsLayout(_ value: Bool) {
        applyingDeferred = true
        super.needsLayout = value
        applyingDeferred = false
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
