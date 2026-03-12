import Foundation
import Testing
@testable import VibeBarCore

@Test func claudeLoaderParsesUsageEntries() async throws {
    let root = try makeTemporaryDirectory(prefix: "claude-loader")
    defer { try? FileManager.default.removeItem(at: root) }

    let projectRoot = root.appendingPathComponent("projects/demo", isDirectory: true)
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    let jsonl = projectRoot.appendingPathComponent("session-1.jsonl", isDirectory: false)
    try """
    {"timestamp":"2026-03-10T10:00:00.000Z","sessionId":"abc","costUSD":0.0042,"message":{"model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000,"output_tokens":200,"cache_creation_input_tokens":50,"cache_read_input_tokens":25}}}
    {"timestamp":"2026-03-10T11:00:00.000Z","sessionId":"abc","message":{"model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":500,"output_tokens":100}}}
    """.write(to: jsonl, atomically: true, encoding: .utf8)

    let result = try await ClaudeUsageLoader(searchRoots: [projectRoot.deletingLastPathComponent()]).load()

    #expect(result.events.count == 2)
    #expect(result.events.first?.source == .claudeCode)
    #expect(result.events.first?.sessionID == "abc")
    #expect(result.events.first?.cacheWriteTokens == 50)
    #expect(result.events.first?.costUSD == 0.0042)
}

@Test func codexLoaderBuildsDeltaEvents() async throws {
    let root = try makeTemporaryDirectory(prefix: "codex-loader")
    defer { try? FileManager.default.removeItem(at: root) }

    let fileURL = root.appendingPathComponent("project-1.jsonl", isDirectory: false)
    try """
    {"timestamp":"2026-03-11T18:25:30.000Z","type":"turn_context","payload":{"model":"gpt-5"}}
    {"timestamp":"2026-03-11T18:25:40.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"cached_input_tokens":200,"output_tokens":500,"reasoning_output_tokens":0,"total_tokens":1700},"last_token_usage":{"input_tokens":1200,"cached_input_tokens":200,"output_tokens":500,"reasoning_output_tokens":0,"total_tokens":1700},"model":"gpt-5"}}}
    {"timestamp":"2026-03-11T18:26:40.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1700,"cached_input_tokens":300,"output_tokens":700,"reasoning_output_tokens":0,"total_tokens":2400},"model":"gpt-5"}}}
    """.write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await CodexUsageLoader(baseDirectory: root).load()

    #expect(result.events.count == 2)
    #expect(result.events[0].inputTokens == 1_200)
    #expect(result.events[1].inputTokens == 500)
    #expect(result.events[1].cacheReadTokens == 100)
    #expect(result.events[1].outputTokens == 200)
}

@Test func opencodeLoaderParsesMessageFiles() async throws {
    let root = try makeTemporaryDirectory(prefix: "opencode-loader")
    defer { try? FileManager.default.removeItem(at: root) }

    let messageRoot = root.appendingPathComponent("storage/message/session-1", isDirectory: true)
    try FileManager.default.createDirectory(at: messageRoot, withIntermediateDirectories: true)
    let messageURL = messageRoot.appendingPathComponent("msg_1.json", isDirectory: false)
    try """
    {"id":"msg_1","sessionID":"session-1","providerID":"anthropic","modelID":"claude-sonnet-4-5","time":{"created":1770000000000},"tokens":{"input":900,"output":300,"cache":{"read":50,"write":20}},"cost":0}
    """.write(to: messageURL, atomically: true, encoding: .utf8)

    let result = try await OpenCodeUsageLoader(baseDirectory: root).load()

    #expect(result.events.count == 1)
    #expect(result.events[0].source == .opencode)
    #expect(result.events[0].sessionID == "session-1")
    #expect(result.events[0].modelName == "claude-sonnet-4-5")
    #expect(result.events[0].timestamp == Date(timeIntervalSince1970: 1_770_000_000))
    #expect(result.events[0].costUSD == nil)
    #expect(result.events[0].cacheReadTokens == 50)
    #expect(result.events[0].cacheWriteTokens == 20)
}

@Test func claudeLoaderRemovesDeletedFilesFromCache() async throws {
    let root = try makeTemporaryDirectory(prefix: "claude-loader-cache")
    defer { try? FileManager.default.removeItem(at: root) }

    let cacheDirectory = root.appendingPathComponent("cache", isDirectory: true)
    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

    let projectRoot = root.appendingPathComponent("projects/demo", isDirectory: true)
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    let jsonl = projectRoot.appendingPathComponent("session-1.jsonl", isDirectory: false)
    try """
    {"timestamp":"2026-03-10T10:00:00.000Z","sessionId":"abc","message":{"model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000,"output_tokens":200}}}
    """.write(to: jsonl, atomically: true, encoding: .utf8)

    let cacheStore = UsageFileCacheStore(baseURL: cacheDirectory)
    let first = try await ClaudeUsageLoader(
        searchRoots: [projectRoot.deletingLastPathComponent()],
        cacheStore: cacheStore
    ).load()
    #expect(first.events.count == 1)

    try FileManager.default.removeItem(at: jsonl)

    let second = try await ClaudeUsageLoader(
        searchRoots: [projectRoot.deletingLastPathComponent()],
        cacheStore: cacheStore
    ).load()
    #expect(second.events.isEmpty)
}

private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
