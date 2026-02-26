import Foundation

public enum WrapperCommandPresence: Sendable, Equatable {
    case notInstalled
    case installedManaged(path: String)
    case installedExternal(path: String)
}

public struct WrapperCommandUpdateInfo: Sendable, Equatable {
    public var installedVersion: String
    public var bundledVersion: String

    public init(installedVersion: String, bundledVersion: String) {
        self.installedVersion = installedVersion
        self.bundledVersion = bundledVersion
    }
}

public enum WrapperCommandDetection: Sendable, Equatable {
    case notInstalled
    case installedManaged(path: String, installedVersion: String?, update: WrapperCommandUpdateInfo?)
    case installedExternal(path: String)
}

public final class WrapperCommandInstaller: Sendable {
    private enum Const {
        static let command = "vibebar"
        static let managedBinFolder = "bin"
        static let managedVersionFile = "vibebar.version"
        static let pathMarkerStart = "# >>> VibeBar vibebar PATH >>>"
        static let pathMarkerEnd = "# <<< VibeBar vibebar PATH <<<"
        static let pathExportLine = "export PATH=\"$HOME/.local/bin:$PATH\""
    }

    public init() {}

    public func detect() -> WrapperCommandPresence {
        let currentPATH = interactiveShellPATH()
        guard let commandURL = resolveCommandFromPATH(currentPATH) else {
            return .notInstalled
        }
        if isManagedCommandPath(commandURL) {
            return .installedManaged(path: commandURL.path)
        }
        return .installedExternal(path: commandURL.path)
    }

    public func detectDetailed() -> WrapperCommandDetection {
        let presence = detect()
        switch presence {
        case .notInstalled:
            return .notInstalled
        case .installedManaged(let path):
            let installedVersion = readInstalledManagedVersion()
            return .installedManaged(
                path: path,
                installedVersion: installedVersion,
                update: detectManagedUpdate(installedVersion: installedVersion)
            )
        case .installedExternal(let path):
            return .installedExternal(path: path)
        }
    }

    public func install() throws {
        let fm = FileManager.default

        let bundledBinary = try locateBundledCommandBinary()
        let managedBin = managedBinDirectory
        let managedBinary = managedBinaryURL

        try fm.createDirectory(at: managedBin, withIntermediateDirectories: true)
        try replaceFile(from: bundledBinary, to: managedBinary)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: managedBinary.path)
        try writeInstalledManagedVersion(currentAppVersion())

        try fm.createDirectory(at: localBinDirectory, withIntermediateDirectories: true)
        try installManagedSymlink()
        try ensureZProfilePATHEntry()

        let status = detect()
        guard case .installedManaged = status else {
            throw makeError(
                "安装完成但未生效，请重新打开终端后重试。若仍失败，请确认 PATH 包含 ~/.local/bin。"
            )
        }
    }

    public func uninstall() throws {
        let fm = FileManager.default

        if case .installedManaged(let commandPath) = detect() {
            let commandURL = URL(fileURLWithPath: commandPath)
            try removeIfManaged(commandURL)
        }

        try removeIfManaged(localCommandLinkURL)

        if fm.fileExists(atPath: managedBinaryURL.path) {
            try fm.removeItem(at: managedBinaryURL)
        }
        if fm.fileExists(atPath: managedVersionFileURL.path) {
            try fm.removeItem(at: managedVersionFileURL)
        }

        try removeZProfilePATHEntry()
    }

    public func update() throws {
        guard case .installedManaged = detect() else {
            throw makeError("仅支持更新由 VibeBar 管理安装的 vibebar 命令。")
        }
        try install()
    }

    // MARK: - Paths

    private var managedBinDirectory: URL {
        VibeBarPaths.appSupportDirectory
            .appendingPathComponent(Const.managedBinFolder, isDirectory: true)
    }

    private var managedBinaryURL: URL {
        managedBinDirectory.appendingPathComponent(Const.command, isDirectory: false)
    }

    private var localBinDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
    }

    private var managedVersionFileURL: URL {
        managedBinDirectory.appendingPathComponent(Const.managedVersionFile, isDirectory: false)
    }

    private var localCommandLinkURL: URL {
        localBinDirectory.appendingPathComponent(Const.command, isDirectory: false)
    }

    private var zProfileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zprofile", isDirectory: false)
    }

    // MARK: - Detection Helpers

    private func interactiveShellPATH() -> String {
        if let path = runZshPATH(arguments: ["-lic", "echo $PATH"], timeout: 2.0) {
            return path
        }
        if let path = runZshPATH(arguments: ["-lc", "echo $PATH"], timeout: 1.5) {
            return path
        }
        return VibeBarPaths.userPATH
    }

    private func runZshPATH(arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 0.3)
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { return nil }
        let lines = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let path = lines?.last, path.contains("/") {
            return path
        }
        return nil
    }

    private func resolveCommandFromPATH(_ pathValue: String) -> URL? {
        let fm = FileManager.default
        for dir in pathValue.split(separator: ":").map(String.init) {
            guard !dir.isEmpty else { continue }
            let candidate = URL(fileURLWithPath: dir, isDirectory: true)
                .appendingPathComponent(Const.command, isDirectory: false)
            if fm.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func isManagedCommandPath(_ path: URL) -> Bool {
        let standardizedManaged = managedBinaryURL.standardizedFileURL.path
        let standardizedPath = path.standardizedFileURL.path
        if standardizedPath == standardizedManaged {
            return true
        }
        return path.resolvingSymlinksInPath().standardizedFileURL.path == standardizedManaged
    }

    private func detectManagedUpdate(installedVersion: String?) -> WrapperCommandUpdateInfo? {
        guard let installedVersion else { return nil }
        let bundledVersion = currentAppVersion()
        guard installedVersion != bundledVersion else { return nil }
        guard isVersionNewer(bundledVersion, than: installedVersion) else { return nil }
        return WrapperCommandUpdateInfo(
            installedVersion: installedVersion,
            bundledVersion: bundledVersion
        )
    }

    private func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private func readInstalledManagedVersion() -> String? {
        if let stamped = readInstalledManagedVersionFromFile(), !stamped.isEmpty {
            return stamped
        }
        return readVersionFromBinary(managedBinaryURL)
    }

    private func readInstalledManagedVersionFromFile() -> String? {
        guard let raw = try? String(contentsOf: managedVersionFileURL, encoding: .utf8) else { return nil }
        let version = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { return nil }
        return version
    }

    private func writeInstalledManagedVersion(_ version: String) throws {
        try version.write(to: managedVersionFileURL, atomically: true, encoding: .utf8)
    }

    private func readVersionFromBinary(_ binaryURL: URL) -> String? {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: binaryURL.path) else { return nil }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--version"]
        process.environment = VibeBarPaths.childProcessEnvironment
        process.standardInput = FileHandle.nullDevice
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parseSemver(from: text)
    }

    private func parseSemver(from text: String) -> String? {
        if let match = text.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) {
            return String(text[match])
        }
        return nil
    }

    private func isVersionNewer(_ lhs: String, than rhs: String) -> Bool {
        guard let lParts = semverComponents(from: lhs) else { return false }
        guard let rParts = semverComponents(from: rhs) else { return true }
        for i in 0..<3 {
            if lParts[i] > rParts[i] { return true }
            if lParts[i] < rParts[i] { return false }
        }
        return false
    }

    private func semverComponents(from version: String) -> [Int]? {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return parts
    }

    // MARK: - Install Helpers

    private func locateBundledCommandBinary() throws -> URL {
        let fm = FileManager.default
        let executable = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()
        let sibling = executable
            .deletingLastPathComponent()
            .appendingPathComponent(Const.command, isDirectory: false)
        if fm.isExecutableFile(atPath: sibling.path) {
            return sibling
        }

        if let repoRoot = VibeBarPaths.repoRoot {
            let candidates: [URL] = [
                repoRoot.appendingPathComponent(".build/debug/vibebar"),
                repoRoot.appendingPathComponent(".build/release/vibebar"),
                repoRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/vibebar"),
                repoRoot.appendingPathComponent(".build/arm64-apple-macosx/release/vibebar"),
                repoRoot.appendingPathComponent(".build/x86_64-apple-macosx/debug/vibebar"),
                repoRoot.appendingPathComponent(".build/x86_64-apple-macosx/release/vibebar"),
                repoRoot.appendingPathComponent(".build/apple/Products/Release/vibebar"),
            ]
            if let matched = candidates.first(where: { fm.isExecutableFile(atPath: $0.path) }) {
                return matched
            }
        }

        throw makeError("未找到可安装的 vibebar。请先执行 swift build --product vibebar。")
    }

    private func replaceFile(from source: URL, to destination: URL) throws {
        let fm = FileManager.default

        if source.standardizedFileURL.path == destination.standardizedFileURL.path {
            return
        }

        let tmp = destination
            .deletingLastPathComponent()
            .appendingPathComponent("\(Const.command).\(UUID().uuidString).tmp", isDirectory: false)
        if fm.fileExists(atPath: tmp.path) {
            try fm.removeItem(at: tmp)
        }

        try fm.copyItem(at: source, to: tmp)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tmp, to: destination)
    }

    private func installManagedSymlink() throws {
        let fm = FileManager.default
        let link = localCommandLinkURL
        if itemExists(link) {
            guard isManagedCommandPath(link) else {
                throw makeError("检测到 \(link.path) 已存在且不属于 VibeBar 管理，已停止覆盖。")
            }
            try fm.removeItem(at: link)
        }
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: managedBinaryURL.path)
    }

    // MARK: - Zsh PATH Helpers

    private func ensureZProfilePATHEntry() throws {
        var content = (try? String(contentsOf: zProfileURL, encoding: .utf8)) ?? ""
        guard !content.contains(Const.pathMarkerStart) else { return }

        let block = [
            Const.pathMarkerStart,
            Const.pathExportLine,
            Const.pathMarkerEnd,
        ].joined(separator: "\n")

        if !content.isEmpty, !content.hasSuffix("\n") {
            content += "\n"
        }
        content += "\n\(block)\n"
        try content.write(to: zProfileURL, atomically: true, encoding: .utf8)
    }

    private func removeZProfilePATHEntry() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: zProfileURL.path) else { return }
        var content = try String(contentsOf: zProfileURL, encoding: .utf8)

        guard let start = content.range(of: Const.pathMarkerStart),
              let end = content.range(of: Const.pathMarkerEnd, range: start.lowerBound..<content.endIndex)
        else { return }

        var upperBound = end.upperBound
        if upperBound < content.endIndex, content[upperBound] == "\n" {
            upperBound = content.index(after: upperBound)
        }
        content.removeSubrange(start.lowerBound..<upperBound)
        try content.write(to: zProfileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Uninstall Helpers

    private func removeIfManaged(_ path: URL) throws {
        let fm = FileManager.default
        guard itemExists(path) else { return }
        guard isManagedCommandPath(path) else { return }
        try fm.removeItem(at: path)
    }

    private func itemExists(_ path: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: path.path) {
            return true
        }
        return (try? fm.destinationOfSymbolicLink(atPath: path.path)) != nil
    }

    // MARK: - Error

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "WrapperCommandInstaller",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
