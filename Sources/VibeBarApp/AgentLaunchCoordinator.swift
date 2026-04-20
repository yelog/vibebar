import Foundation
import VibeBarCore

struct AgentLaunchCoordinator {
    struct Result {
        var process: Process?
        var startedNewProcess: Bool
        var removedStaleSocket: Bool
        var error: Error?

        var attemptedStartup: Bool {
            startedNewProcess || error != nil
        }
    }

    struct Environment {
        var socketPath: String
        var socketReachability: @Sendable (String) -> Bool
        var isAgentProcessRunning: @Sendable () -> Bool
        var socketFileExists: @Sendable (String) -> Bool
        var removeSocketFile: @Sendable (String) throws -> Void
        var startAgent: @Sendable () throws -> Process

        static func live() -> Environment {
            Environment(
                socketPath: VibeBarPaths.agentSocketURL.path,
                socketReachability: { AgentSocketClient(socketPath: $0).canConnect() },
                isAgentProcessRunning: {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
                    process.arguments = ["-f", "vibebar-agent"]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    process.standardInput = FileHandle.nullDevice
                    do {
                        try process.run()
                        process.waitUntilExit()
                        return process.terminationStatus == 0
                    } catch {
                        return false
                    }
                },
                socketFileExists: { FileManager.default.fileExists(atPath: $0) },
                removeSocketFile: { path in
                    try? FileManager.default.removeItem(atPath: path)
                },
                startAgent: {
                    let exe = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
                        .resolvingSymlinksInPath()
                    let agentURL = exe.deletingLastPathComponent()
                        .appendingPathComponent("vibebar-agent")
                    guard FileManager.default.isExecutableFile(atPath: agentURL.path) else {
                        throw LaunchError.executableNotFound(agentURL.path)
                    }

                    let process = Process()
                    process.executableURL = agentURL
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    process.standardInput = FileHandle.nullDevice
                    try process.run()
                    return process
                }
            )
        }
    }

    enum LaunchError: LocalizedError {
        case executableNotFound(String)
        case staleSocketCleanupFailed(String, Error)
        case startFailed(Error)

        var errorDescription: String? {
            switch self {
            case .executableNotFound(let path):
                return "找不到 vibebar-agent 可执行文件：\(path)"
            case .staleSocketCleanupFailed(let path, let error):
                return "无法清理遗留 socket：\(path)，\(error.localizedDescription)"
            case .startFailed(let error):
                return "启动 vibebar-agent 失败：\(error.localizedDescription)"
            }
        }
    }

    private let environment: Environment

    init(environment: Environment = .live()) {
        self.environment = environment
    }

    func ensureAgentAvailable() -> Result {
        let socketPath = environment.socketPath
        if environment.socketReachability(socketPath) {
            return Result(
                process: nil,
                startedNewProcess: false,
                removedStaleSocket: false,
                error: nil
            )
        }

        if environment.isAgentProcessRunning() {
            return Result(
                process: nil,
                startedNewProcess: false,
                removedStaleSocket: false,
                error: nil
            )
        }

        var removedStaleSocket = false
        if environment.socketFileExists(socketPath) {
            do {
                try environment.removeSocketFile(socketPath)
                removedStaleSocket = true
            } catch {
                return Result(
                    process: nil,
                    startedNewProcess: false,
                    removedStaleSocket: false,
                    error: LaunchError.staleSocketCleanupFailed(socketPath, error)
                )
            }
        }

        do {
            let process = try environment.startAgent()
            return Result(
                process: process,
                startedNewProcess: true,
                removedStaleSocket: removedStaleSocket,
                error: nil
            )
        } catch let launchError as LaunchError {
            return Result(
                process: nil,
                startedNewProcess: false,
                removedStaleSocket: removedStaleSocket,
                error: launchError
            )
        } catch {
            return Result(
                process: nil,
                startedNewProcess: false,
                removedStaleSocket: removedStaleSocket,
                error: LaunchError.startFailed(error)
            )
        }
    }
}
