import Darwin
import Foundation

public struct AgentSocketClient: Sendable {
    public var socketPath: String

    public init(socketPath: String = VibeBarPaths.agentSocketURL.path) {
        self.socketPath = socketPath
    }

    public func send(_ envelope: AgentEnvelope) -> Bool {
        guard let data = Self.encodedData(for: envelope) else { return false }
        return withConnectedSocket { fd in
            writeAll(data, to: fd)
        } ?? false
    }

    public func send(_ event: AgentEvent) -> Bool {
        send(AgentEnvelope(kind: .event, event: event))
    }

    public func sendAndWait(
        _ envelope: AgentEnvelope,
        timeout: TimeInterval
    ) -> AgentInteractionResponse? {
        guard let data = Self.encodedData(for: envelope) else { return nil }

        return withConnectedSocketOptional { fd in
            guard writeAll(data, to: fd) else { return nil }
            guard shutdown(fd, SHUT_WR) == 0 else { return nil }
            return readResponse(from: fd, timeout: timeout)
        }
    }

    public static func encodedData(for envelope: AgentEnvelope) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(envelope) else { return nil }
        data.append(0x0A)
        return data
    }

    private func withConnectedSocket<Result>(
        _ body: (Int32) -> Result
    ) -> Result? {
        guard let fd = connectSocket() else { return nil }
        defer { close(fd) }
        return body(fd)
    }

    private func withConnectedSocketOptional<Result>(
        _ body: (Int32) -> Result?
    ) -> Result? {
        guard let fd = connectSocket() else { return nil }
        defer { close(fd) }
        return body(fd)
    }

    private func connectSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        let utf8Path = socketPath.utf8CString
        guard utf8Path.count <= maxPathLength else {
            close(fd)
            return nil
        }

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
        guard connectResult == 0 else {
            close(fd)
            return nil
        }

        return fd
    }

    private func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            var written = 0
            while written < rawBuffer.count {
                let count = write(fd, baseAddress.advanced(by: written), rawBuffer.count - written)
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

    private func readResponse(from fd: Int32, timeout: TimeInterval) -> AgentInteractionResponse? {
        var tv = timeval(
            tv_sec: Int(timeout.rounded(.down)),
            tv_usec: __darwin_suseconds_t((timeout - floor(timeout)) * 1_000_000)
        )
        guard setsockopt(
            fd,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &tv,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: 4096)
        var data = Data()

        while true {
            let count = read(fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            data.append(buffer, count: count)
        }

        guard !data.isEmpty else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            guard let lineData = line.data(using: .utf8) else { continue }
            if let envelope = try? decoder.decode(AgentEnvelope.self, from: lineData),
               let response = envelope.response {
                return response
            }
            if let response = try? decoder.decode(AgentInteractionResponse.self, from: lineData) {
                return response
            }
        }

        return nil
    }
}
