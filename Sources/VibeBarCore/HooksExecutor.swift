import Foundation

public final class HooksExecutor: @unchecked Sendable {
    public static let shared = HooksExecutor()

    private let store = HooksConfigStore()
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private let lock = NSLock()

    private init() {}

    public func trigger(
        _ trigger: HookTrigger,
        session: SessionSnapshot,
        previousState: ToolActivityState? = nil
    ) {
        let config = store.load()
        let matchingHooks = config.hooks.filter { hook in
            hook.isEnabled &&
            hook.triggers.contains(trigger) &&
            (hook.tools?.contains(session.tool) ?? true)
        }

        guard !matchingHooks.isEmpty else { return }

        for hook in matchingHooks {
            let taskID = "\(hook.id)-\(UUID().uuidString)"
            let task = Task.detached(priority: .utility) { [weak self] in
                await self?.execute(hook, trigger: trigger, session: session, previousState: previousState)
                self?.removeTask(id: taskID)
            }
            lock.lock()
            activeTasks[taskID] = task
            lock.unlock()
        }
    }

    private func removeTask(id: String) {
        lock.lock()
        activeTasks.removeValue(forKey: id)
        lock.unlock()
    }

    public func cancelAll() {
        lock.lock()
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        lock.unlock()
    }

    private func execute(
        _ hook: HookConfig,
        trigger: HookTrigger,
        session: SessionSnapshot,
        previousState: ToolActivityState?
    ) async {
        let context = HookContext(
            trigger: trigger,
            session: session,
            previousState: previousState
        )

        switch hook.action.type {
        case .shell:
            await executeShell(hook.action, context: context, hookName: hook.name)
        case .webhook:
            await executeWebhook(hook.action, context: context, hookName: hook.name)
        }
    }

    private func executeShell(_ action: HookAction, context: HookContext, hookName: String) async {
        guard let command = action.shellCommand, !command.isEmpty else { return }

        let timeout = action.timeout
        let env = context.environment

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]

                var environment = ProcessInfo.processInfo.environment
                for (key, value) in env {
                    environment[key] = value
                }
                process.environment = environment

                let stdout = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdout
                process.standardError = stderrPipe
                process.standardInput = FileHandle.nullDevice

                let semaphore = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in
                    semaphore.signal()
                }

                do {
                    try process.run()
                } catch {
                    fputs("vibebar: Hook '\(hookName)' failed to start: \(error.localizedDescription)\n", stderr)
                    continuation.resume()
                    return
                }

                let result = semaphore.wait(timeout: .now() + timeout)
                if result == .timedOut {
                    process.terminate()
                    fputs("vibebar: Hook '\(hookName)' timed out after \(timeout)s\n", stderr)
                    continuation.resume()
                    return
                }

                let exitCode = process.terminationStatus
                if exitCode != 0 {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
                    fputs("vibebar: Hook '\(hookName)' exited with code \(exitCode): \(stderrText.trimmingCharacters(in: .whitespacesAndNewlines))\n", stderr)
                }

                continuation.resume()
            }
        }
    }

    private func executeWebhook(_ action: HookAction, context: HookContext, hookName: String) async {
        guard let urlString = action.webhookURL,
              let url = URL(string: urlString) else {
            fputs("vibebar: Hook '\(hookName)' has invalid webhook URL\n", stderr)
            return
        }

        guard let payload = context.jsonPayload else {
            fputs("vibebar: Hook '\(hookName)' failed to serialize payload\n", stderr)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = action.webhookMethod ?? "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = action.timeout

        if let headers = action.webhookHeaders {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                if !(200..<300).contains(statusCode) {
                    fputs("vibebar: Hook '\(hookName)' webhook returned HTTP \(statusCode)\n", stderr)
                }
            }
        } catch {
            fputs("vibebar: Hook '\(hookName)' webhook failed: \(error.localizedDescription)\n", stderr)
        }
    }

    public func test(_ hook: HookConfig) async throws {
        let dummySession = SessionSnapshot(
            id: "test-session-id",
            tool: .claudeCode,
            pid: 12345,
            status: .idle,
            source: .plugin,
            startedAt: Date(),
            updatedAt: Date(),
            cwd: "/Users/test/project",
            command: ["claude"]
        )

        let context = HookContext(
            trigger: hook.triggers.first ?? .sessionStarted,
            session: dummySession,
            previousState: .running
        )

        switch hook.action.type {
        case .shell:
            await executeShell(hook.action, context: context, hookName: hook.name)
        case .webhook:
            await executeWebhook(hook.action, context: context, hookName: hook.name)
        }
    }
}