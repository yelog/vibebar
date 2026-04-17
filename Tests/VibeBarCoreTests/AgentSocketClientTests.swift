import Darwin
import Foundation
import Testing
@testable import VibeBarCore

@Test func agentSocketClientSendsEventEnvelope() throws {
    let server = try AgentSocketTestServer()
    defer { server.stop() }
    try server.start()

    let client = AgentSocketClient(socketPath: server.socketPath)
    let event = AgentEvent(
        source: .codexHook,
        tool: .codex,
        sessionID: "sess-event",
        eventType: "session_start",
        status: .running,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000)
    )

    #expect(client.send(AgentEnvelope(kind: .event, event: event)))

    let received = try #require(server.waitForEnvelope())
    #expect(received.kind == .event)
    #expect(received.event?.sessionID == "sess-event")
    #expect(received.event?.eventType == "session_start")
}

@Test func agentSocketClientSendsInteractionRequestAndWaitsForResponse() throws {
    let server = try AgentSocketTestServer()
    defer { server.stop() }

    let request = PendingInteraction(
        id: "interaction-1",
        sessionID: "plugin-codex-hook-sess-1",
        tool: .codex,
        kind: .permission,
        message: "允许执行吗？",
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let expectedResponse = AgentInteractionResponse(
        requestID: request.id,
        decision: InteractionDecision(behavior: .allow)
    )

    try server.start(
        responseEnvelope: AgentEnvelope(
            kind: .interactionResponse,
            response: expectedResponse
        )
    )

    let client = AgentSocketClient(socketPath: server.socketPath)
    let response = client.sendAndWait(
        AgentEnvelope(kind: .interactionRequest, request: request),
        timeout: 1
    )

    let received = try #require(server.waitForEnvelope())
    #expect(received.kind == .interactionRequest)
    #expect(received.request?.id == request.id)
    #expect(response?.requestID == request.id)
    #expect(response?.decision?.behavior == .allow)
}

private final class AgentSocketTestServer: @unchecked Sendable {
    let socketPath: String

    private let listenFD: Int32
    private let stateQueue = DispatchQueue(label: "AgentSocketTestServer.state")
    private let receivedSemaphore = DispatchSemaphore(value: 0)
    private var receivedEnvelope: AgentEnvelope?

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        socketPath = directory.appendingPathComponent("agent.sock").path

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        if listenFD < 0 {
            throw POSIXError(.ENOTSOCK)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let utf8Path = socketPath.utf8CString
        guard utf8Path.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(listenFD)
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            _ = utf8Path.withUnsafeBufferPointer { pathPtr in
                memcpy(sunPathPtr, pathPtr.baseAddress, pathPtr.count)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(listenFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.stride))
            }
        }
        guard bindResult == 0, listen(listenFD, 8) == 0 else {
            close(listenFD)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func start(responseEnvelope: AgentEnvelope? = nil) throws {
        DispatchQueue.global(qos: .userInitiated).async { [listenFD, stateQueue, receivedSemaphore] in
            let clientFD = accept(listenFD, nil, nil)
            guard clientFD >= 0 else { return }
            defer { close(clientFD) }

            var buffer = [UInt8](repeating: 0, count: 4096)
            var data = Data()
            while true {
                let count = read(clientFD, &buffer, buffer.count)
                if count == 0 { break }
                if count < 0 {
                    if errno == EINTR { continue }
                    return
                }
                data.append(buffer, count: count)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let text = String(data: data, encoding: .utf8) {
                for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                    guard let lineData = line.data(using: .utf8) else { continue }
                    if let envelope = try? decoder.decode(AgentEnvelope.self, from: lineData) {
                        stateQueue.sync {
                            self.receivedEnvelope = envelope
                        }
                        receivedSemaphore.signal()
                        break
                    }
                }
            }

            if let responseEnvelope,
               let responseData = AgentSocketClient.encodedData(for: responseEnvelope) {
                _ = responseData.withUnsafeBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress else { return false }
                    var written = 0
                    while written < rawBuffer.count {
                        let count = write(clientFD, baseAddress.advanced(by: written), rawBuffer.count - written)
                        if count < 0 {
                            if errno == EINTR { continue }
                            return false
                        }
                        if count == 0 {
                            return false
                        }
                        written += count
                    }
                    return true
                }
            }
        }
    }

    func waitForEnvelope(timeout: TimeInterval = 1) -> AgentEnvelope? {
        let result = receivedSemaphore.wait(timeout: .now() + timeout)
        guard result == .success else { return nil }
        return stateQueue.sync { receivedEnvelope }
    }

    func stop() {
        close(listenFD)
        try? FileManager.default.removeItem(atPath: socketPath)
        try? FileManager.default.removeItem(atPath: (socketPath as NSString).deletingLastPathComponent)
    }
}
