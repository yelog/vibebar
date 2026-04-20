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
        var shouldRestartReachableAgent: @Sendable (String) -> Bool
        var removeSocketFile: @Sendable (String) throws -> Void
        var terminateAgentProcess: @Sendable () -> Bool
        var startAgent: @Sendable () throws -> Process

        init(
            socketPath: String,
            socketReachability: @escaping @Sendable (String) -> Bool,
            isAgentProcessRunning: @escaping @Sendable () -> Bool,
            socketFileExists: @escaping @Sendable (String) -> Bool,
            shouldRestartReachableAgent: @escaping @Sendable (String) -> Bool = { _ in false },
            removeSocketFile: @escaping @Sendable (String) throws -> Void,
            terminateAgentProcess: @escaping @Sendable () -> Bool = { true },
            startAgent: @escaping @Sendable () throws -> Process
        ) {
            self.socketPath = socketPath
            self.socketReachability = socketReachability
            self.isAgentProcessRunning = isAgentProcessRunning
            self.socketFileExists = socketFileExists
            self.shouldRestartReachableAgent = shouldRestartReachableAgent
            self.removeSocketFile = removeSocketFile
            self.terminateAgentProcess = terminateAgentProcess
            self.startAgent = startAgent
        }

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
                shouldRestartReachableAgent: { socketPath in
                    let exe = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
                        .resolvingSymlinksInPath()
                    let agentURL = exe.deletingLastPathComponent()
                        .appendingPathComponent("vibebar-agent")
                    return AgentLaunchCoordinator.shouldRestartAgent(
                        executablePath: agentURL.path,
                        socketPath: socketPath
                    )
                },
                removeSocketFile: { path in
                    try? FileManager.default.removeItem(atPath: path)
                },
                terminateAgentProcess: {
                    AgentLaunchCoordinator.terminateAgentProcess()
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
        case restartFailed
        case startFailed(Error)

        var errorDescription: String? {
            switch self {
            case .executableNotFound(let path):
                return "找不到 vibebar-agent 可执行文件：\(path)"
            case .staleSocketCleanupFailed(let path, let error):
                return "无法清理遗留 socket：\(path)，\(error.localizedDescription)"
            case .restartFailed:
                return "无法重启旧版 vibebar-agent"
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
        let shouldRestart = environment.shouldRestartReachableAgent(socketPath)
        if environment.socketReachability(socketPath) {
            if !shouldRestart {
                return Result(
                    process: nil,
                    startedNewProcess: false,
                    removedStaleSocket: false,
                    error: nil
                )
            }
            return restartRunningAgent(socketPath: socketPath)
        }

        if environment.isAgentProcessRunning() {
            if !shouldRestart {
                return Result(
                    process: nil,
                    startedNewProcess: false,
                    removedStaleSocket: false,
                    error: nil
                )
            }
            return restartRunningAgent(socketPath: socketPath)
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

    private func restartRunningAgent(socketPath: String) -> Result {
        guard environment.terminateAgentProcess() else {
            return Result(
                process: nil,
                startedNewProcess: false,
                removedStaleSocket: false,
                error: LaunchError.restartFailed
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

    private static func shouldRestartAgent(
        executablePath: String,
        socketPath: String,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let executableDate = modificationDate(
            at: executablePath,
            fileManager: fileManager
        ), let socketDate = modificationDate(
            at: socketPath,
            fileManager: fileManager
        ) else {
            return false
        }

        return executableDate.timeIntervalSince(socketDate) > 1
    }

    private static func modificationDate(
        at path: String,
        fileManager: FileManager
    ) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    private static func terminateAgentProcess() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-TERM", "-f", "vibebar-agent"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                Thread.sleep(forTimeInterval: 0.3)
                return true
            }
        } catch {}

        return false
    }
}
