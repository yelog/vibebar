import Darwin
import Foundation
import Testing
import VibeBarCore
@testable import VibeBarApp

@Test func interactionActionHandlerRelaysCodexDecisionToAgent() async throws {
    let server = try AppTestAgentSocketServer()
    defer { server.stop() }
    try server.start()

    let handler = InteractionActionHandler(
        socketClient: AgentSocketClient(socketPath: server.socketPath)
    )
    let interaction = PendingInteraction(
        id: "codex-request",
        sessionID: "plugin-codex-hook-sess-1",
        tool: .codex,
        kind: .question,
        message: "请输入你的回答",
        allowsFreeText: true,
        requestedAt: Date()
    )
    let decision = InteractionDecision(
        behavior: .allow,
        metadata: ["answer.answer_1": "直接执行"]
    )

    let success = await handler.submit(
        interaction: interaction,
        decision: decision,
        sessionPID: nil
    )

    #expect(success)
    let envelope = try #require(server.waitForEnvelope())
    #expect(envelope.kind == .interactionResponse)
    #expect(envelope.response?.requestID == interaction.id)
    #expect(envelope.response?.decision?.behavior == .allow)
    #expect(envelope.response?.decision?.metadata["answer.answer_1"] == "直接执行")
}

private final class AppTestAgentSocketServer: @unchecked Sendable {
    let socketPath: String

    private let listenFD: Int32
    private let stateQueue = DispatchQueue(label: "AppTestAgentSocketServer.state")
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

    func start() throws {
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
