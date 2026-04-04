import Darwin
import Foundation
import VibeBarCore

actor InteractionActionHandler {
    static let shared = InteractionActionHandler()

    func submit(requestID: String, decision: InteractionDecision) async -> Bool {
        let response = AgentInteractionResponse(requestID: requestID, decision: decision)
        let envelope = AgentEnvelope(kind: .interactionResponse, response: response)
        return await Task.detached(priority: .userInitiated) {
            Self.send(envelope: envelope)
        }.value
    }

    static func encodedData(for envelope: AgentEnvelope) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(envelope) else { return nil }
        data.append(0x0A)
        return data
    }

    private static func send(envelope: AgentEnvelope) -> Bool {
        guard let data = encodedData(for: envelope) else { return false }
        let socketPath = VibeBarPaths.agentSocketURL.path

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        let utf8Path = socketPath.utf8CString
        guard utf8Path.count <= maxPathLength else { return false }

        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            _ = utf8Path.withUnsafeBufferPointer { pathPtr in
                memcpy(sunPathPtr, pathPtr.baseAddress, pathPtr.count)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.stride))
            }
        }
        guard connectResult == 0 else { return false }

        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            var written = 0
            while written < rawBuffer.count {
                let count = write(fd, baseAddress.advanced(by: written), rawBuffer.count - written)
                if count <= 0 { return false }
                written += count
            }
            return true
        }
    }
}
