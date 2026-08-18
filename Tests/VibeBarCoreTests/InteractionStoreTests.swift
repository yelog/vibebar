import Foundation
import Testing
@testable import VibeBarCore

@Test func interactionStoreLoadsAndPrunesExpiredInOnePass() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = InteractionStore(baseDirectory: directory)
    try store.write(
        PendingInteraction(
            id: "expired",
            sessionID: "session-1",
            tool: .claudeCode,
            kind: .permission,
            message: "旧请求",
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_700_000_010)
        )
    )
    try store.write(
        PendingInteraction(
            id: "active",
            sessionID: "session-1",
            tool: .claudeCode,
            kind: .permission,
            message: "新请求",
            requestedAt: Date(timeIntervalSince1970: 1_700_000_020),
            expiresAt: Date(timeIntervalSince1970: 1_700_000_050)
        )
    )

    let active = store.loadAll(cleaningExpiredAt: Date(timeIntervalSince1970: 1_700_000_030))
    #expect(active.map(\.id) == ["active"])
    #expect(store.load(id: "expired") == nil)
    #expect(store.load(id: "active") != nil)
}

@Test func interactionStoreSinglePassIgnoresMalformedJsonWithoutDeletingValidFiles() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let malformedURL = directory.appendingPathComponent("broken.json")
    try Data("{ not valid json".utf8).write(to: malformedURL)

    let store = InteractionStore(baseDirectory: directory)
    try store.write(
        PendingInteraction(
            id: "valid",
            sessionID: "session-1",
            tool: .opencode,
            kind: .question,
            message: "有效请求",
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_700_000_050)
        )
    )

    let active = store.loadAll(cleaningExpiredAt: Date(timeIntervalSince1970: 1_700_000_030))
    #expect(active.map(\.id) == ["valid"])
    #expect(store.load(id: "valid") != nil)
    #expect(FileManager.default.fileExists(atPath: malformedURL.path))
}

@Test func interactionStoreCanWriteAndLoadInteraction() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = InteractionStore(baseDirectory: directory)
    let interaction = PendingInteraction(
        id: "request-1",
        sessionID: "session-1",
        tool: .opencode,
        kind: .question,
        title: "选择动作",
        message: "下一步做什么？",
        options: [InteractionOption(id: "fix", label: "修复")],
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
        transportContext: ["question_id": "q-1"]
    )

    try store.write(interaction)

    let all = store.loadAll()
    let loaded = try #require(store.load(id: "request-1"))

    #expect(all.count == 1)
    #expect(loaded.message == "下一步做什么？")
    #expect(loaded.transportContext["question_id"] == "q-1")
}

@Test func interactionStoreCanDeleteInteraction() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = InteractionStore(baseDirectory: directory)
    let interaction = PendingInteraction(
        id: "request-2",
        sessionID: "session-2",
        tool: .claudeCode,
        kind: .permission,
        message: "允许写文件吗？",
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    try store.write(interaction)
    store.delete(id: "request-2")

    #expect(store.load(id: "request-2") == nil)
    #expect(store.loadAll().isEmpty)
}

@Test func interactionStoreCleansExpiredInteractions() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = InteractionStore(baseDirectory: directory)
    let expired = PendingInteraction(
        id: "expired",
        sessionID: "session-1",
        tool: .claudeCode,
        kind: .permission,
        message: "旧请求",
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
        expiresAt: Date(timeIntervalSince1970: 1_700_000_010)
    )
    let fresh = PendingInteraction(
        id: "fresh",
        sessionID: "session-1",
        tool: .claudeCode,
        kind: .permission,
        message: "新请求",
        requestedAt: Date(timeIntervalSince1970: 1_700_000_020),
        expiresAt: Date(timeIntervalSince1970: 1_700_000_050)
    )

    try store.write(expired)
    try store.write(fresh)
    store.cleanupExpired(now: Date(timeIntervalSince1970: 1_700_000_030))

    #expect(store.load(id: "expired") == nil)
    #expect(store.load(id: "fresh")?.message == "新请求")
}

@Test func interactionStoreCanDeleteAllForSession() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = InteractionStore(baseDirectory: directory)
    try store.write(
        PendingInteraction(
            id: "request-a",
            sessionID: "session-a",
            tool: .claudeCode,
            kind: .permission,
            message: "A",
            requestedAt: Date()
        )
    )
    try store.write(
        PendingInteraction(
            id: "request-b",
            sessionID: "session-a",
            tool: .claudeCode,
            kind: .permission,
            message: "B",
            requestedAt: Date()
        )
    )
    try store.write(
        PendingInteraction(
            id: "request-c",
            sessionID: "session-c",
            tool: .opencode,
            kind: .question,
            message: "C",
            requestedAt: Date()
        )
    )

    store.deleteAll(sessionID: "session-a")

    #expect(store.load(id: "request-a") == nil)
    #expect(store.load(id: "request-b") == nil)
    #expect(store.load(id: "request-c") != nil)
}
