import Foundation
import Testing
@testable import VibeBarApp

private final class CoordinatorTestState: @unchecked Sendable {
    var didStartAgent = false
    var removedPaths: [String] = []
    var didTerminateAgent = false
}

@Test func coordinatorSkipsStartupWhenSocketIsReachable() {
    let state = CoordinatorTestState()

    let coordinator = AgentLaunchCoordinator(
        environment: .init(
            socketPath: "/tmp/vibebar-agent.sock",
            socketReachability: { _ in true },
            isAgentProcessRunning: { false },
            socketFileExists: { _ in true },
            removeSocketFile: { _ in },
            startAgent: {
                state.didStartAgent = true
                return Process()
            }
        )
    )

    let result = coordinator.ensureAgentAvailable()

    #expect(result.startedNewProcess == false)
    #expect(result.removedStaleSocket == false)
    #expect(result.error == nil)
    #expect(state.didStartAgent == false)
}

@Test func coordinatorRestartsReachableAgentInSourceMode() {
    let state = CoordinatorTestState()

    let coordinator = AgentLaunchCoordinator(
        environment: .init(
            runMode: .source,
            socketPath: "/tmp/vibebar-agent.sock",
            socketReachability: { _ in true },
            isAgentProcessRunning: { true },
            socketFileExists: { _ in true },
            removeSocketFile: { path in
                state.removedPaths.append(path)
            },
            terminateAgentProcess: {
                state.didTerminateAgent = true
                return true
            },
            startAgent: {
                state.didStartAgent = true
                return Process()
            }
        )
    )

    let result = coordinator.ensureAgentAvailable()

    #expect(result.startedNewProcess)
    #expect(result.removedStaleSocket)
    #expect(result.error == nil)
    #expect(state.didTerminateAgent)
    #expect(state.removedPaths == ["/tmp/vibebar-agent.sock"])
    #expect(state.didStartAgent)
}

@Test func coordinatorRestartsReachableAgentWhenExecutableIsNewer() {
    let state = CoordinatorTestState()

    let coordinator = AgentLaunchCoordinator(
        environment: .init(
            socketPath: "/tmp/vibebar-agent.sock",
            socketReachability: { _ in true },
            isAgentProcessRunning: { true },
            socketFileExists: { _ in true },
            shouldRestartReachableAgent: { _ in true },
            removeSocketFile: { path in
                state.removedPaths.append(path)
            },
            terminateAgentProcess: {
                state.didTerminateAgent = true
                return true
            },
            startAgent: {
                state.didStartAgent = true
                return Process()
            }
        )
    )

    let result = coordinator.ensureAgentAvailable()

    #expect(result.startedNewProcess)
    #expect(result.removedStaleSocket)
    #expect(result.error == nil)
    #expect(state.didTerminateAgent)
    #expect(state.removedPaths == ["/tmp/vibebar-agent.sock"])
    #expect(state.didStartAgent)
}

@Test func coordinatorRemovesStaleSocketAndStartsAgentWhenNoProcessExists() {
    let state = CoordinatorTestState()

    let coordinator = AgentLaunchCoordinator(
        environment: .init(
            socketPath: "/tmp/vibebar-agent.sock",
            socketReachability: { _ in false },
            isAgentProcessRunning: { false },
            socketFileExists: { _ in true },
            removeSocketFile: { path in
                state.removedPaths.append(path)
            },
            startAgent: {
                state.didStartAgent = true
                return Process()
            }
        )
    )

    let result = coordinator.ensureAgentAvailable()

    #expect(result.startedNewProcess)
    #expect(result.removedStaleSocket)
    #expect(result.error == nil)
    #expect(state.removedPaths == ["/tmp/vibebar-agent.sock"])
    #expect(state.didStartAgent)
}

@Test func coordinatorDoesNotDeleteSocketWhenProcessStillExists() {
    let state = CoordinatorTestState()

    let coordinator = AgentLaunchCoordinator(
        environment: .init(
            socketPath: "/tmp/vibebar-agent.sock",
            socketReachability: { _ in false },
            isAgentProcessRunning: { true },
            socketFileExists: { _ in true },
            removeSocketFile: { path in
                state.removedPaths.append(path)
            },
            startAgent: {
                state.didStartAgent = true
                return Process()
            }
        )
    )

    let result = coordinator.ensureAgentAvailable()

    #expect(result.startedNewProcess == false)
    #expect(result.removedStaleSocket == false)
    #expect(result.error == nil)
    #expect(state.removedPaths.isEmpty)
    #expect(state.didStartAgent == false)
}

@Test func coordinatorReportsFailureWhenReachableAgentCannotBeRestarted() {
    let state = CoordinatorTestState()

    let coordinator = AgentLaunchCoordinator(
        environment: .init(
            socketPath: "/tmp/vibebar-agent.sock",
            socketReachability: { _ in true },
            isAgentProcessRunning: { true },
            socketFileExists: { _ in true },
            shouldRestartReachableAgent: { _ in true },
            removeSocketFile: { path in
                state.removedPaths.append(path)
            },
            terminateAgentProcess: {
                state.didTerminateAgent = true
                return false
            },
            startAgent: {
                state.didStartAgent = true
                return Process()
            }
        )
    )

    let result = coordinator.ensureAgentAvailable()

    #expect(result.startedNewProcess == false)
    #expect(result.removedStaleSocket == false)
    #expect(result.error != nil)
    #expect(state.didTerminateAgent)
    #expect(state.removedPaths.isEmpty)
    #expect(state.didStartAgent == false)
}

@Test func coordinatorReportsFailureWhenStartThrows() {
    struct StubError: Error {}

    let coordinator = AgentLaunchCoordinator(
        environment: .init(
            socketPath: "/tmp/vibebar-agent.sock",
            socketReachability: { _ in false },
            isAgentProcessRunning: { false },
            socketFileExists: { _ in false },
            removeSocketFile: { _ in },
            startAgent: {
                throw StubError()
            }
        )
    )

    let result = coordinator.ensureAgentAvailable()

    #expect(result.startedNewProcess == false)
    #expect(result.removedStaleSocket == false)
    #expect(result.attemptedStartup)
    #expect(result.error != nil)
}

@Test func coordinatorTerminatesExistingAgentInSourceModeOnShutdown() {
    let state = CoordinatorTestState()

    let coordinator = AgentLaunchCoordinator(
        environment: .init(
            runMode: .source,
            socketPath: "/tmp/vibebar-agent.sock",
            socketReachability: { _ in true },
            isAgentProcessRunning: { true },
            socketFileExists: { _ in true },
            removeSocketFile: { _ in },
            terminateAgentProcess: {
                state.didTerminateAgent = true
                return true
            },
            startAgent: {
                state.didStartAgent = true
                return Process()
            }
        )
    )

    let cleaned = coordinator.cleanupAgentOnTerminate()

    #expect(cleaned)
    #expect(state.didTerminateAgent)
    #expect(state.didStartAgent == false)
}

@Test func coordinatorSkipsShutdownCleanupInPublishedMode() {
    let state = CoordinatorTestState()

    let coordinator = AgentLaunchCoordinator(
        environment: .init(
            runMode: .published,
            socketPath: "/tmp/vibebar-agent.sock",
            socketReachability: { _ in true },
            isAgentProcessRunning: { true },
            socketFileExists: { _ in true },
            removeSocketFile: { _ in },
            terminateAgentProcess: {
                state.didTerminateAgent = true
                return true
            },
            startAgent: {
                state.didStartAgent = true
                return Process()
            }
        )
    )

    let cleaned = coordinator.cleanupAgentOnTerminate()

    #expect(cleaned == false)
    #expect(state.didTerminateAgent == false)
    #expect(state.didStartAgent == false)
}
