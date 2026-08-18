import Foundation
import Testing
@testable import VibeBarCore

private func makeJSONLFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: false)
    return url
}

@Test func incrementalReaderInitialFullRead() throws {
    let url = try makeJSONLFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\nb\nc\n".utf8).write(to: url)

    let result = try #require(IncrementalJSONLReader.readLines(from: url, state: nil))

    #expect(result.lines == ["a", "b", "c"])
    #expect(result.state.partialLine.isEmpty)
    #expect(result.state.byteOffset == "a\nb\nc\n".utf8.count)
}

@Test func incrementalReaderAppendedCompleteLines() throws {
    let url = try makeJSONLFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\n".utf8).write(to: url)

    let first = try #require(IncrementalJSONLReader.readLines(from: url, state: nil))
    #expect(first.lines == ["a"])

    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("b\nc\n".utf8))
    try handle.close()

    let second = try #require(IncrementalJSONLReader.readLines(from: url, state: first.state))
    #expect(second.lines == ["b", "c"])
    #expect(second.state.byteOffset > first.state.byteOffset)
}

@Test func incrementalReaderPartialLineAtEnd() throws {
    let url = try makeJSONLFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\npartial".utf8).write(to: url)

    let first = try #require(IncrementalJSONLReader.readLines(from: url, state: nil))

    #expect(first.lines == ["a"])
    #expect(first.state.partialLine == Data("partial".utf8))
    #expect(first.state.byteOffset == "a\n".utf8.count)
}

@Test func incrementalReaderCompletesPartialLine() throws {
    let url = try makeJSONLFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\npart".utf8).write(to: url)

    let first = try #require(IncrementalJSONLReader.readLines(from: url, state: nil))
    #expect(first.lines == ["a"])
    #expect(first.state.partialLine == Data("part".utf8))

    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("ial\nb\n".utf8))
    try handle.close()

    let second = try #require(IncrementalJSONLReader.readLines(from: url, state: first.state))
    #expect(second.lines == ["partial", "b"])
    #expect(second.state.partialLine.isEmpty)
}

@Test func incrementalReaderDetectsTruncation() throws {
    let url = try makeJSONLFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\nb\nc\n".utf8).write(to: url)

    let first = try #require(IncrementalJSONLReader.readLines(from: url, state: nil))
    #expect(first.state.byteOffset > 0)

    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: 2)
    try handle.close()

    let second = try #require(IncrementalJSONLReader.readLines(from: url, state: first.state))
    #expect(second.lines == ["a"])
}

@Test func incrementalReaderDetectsAtomicReplacement() throws {
    let url = try makeJSONLFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\nb\n".utf8).write(to: url)

    let first = try #require(IncrementalJSONLReader.readLines(from: url, state: nil))
    #expect(first.lines == ["a", "b"])

    try Data("x\ny\n".utf8).write(to: url, options: .atomic)

    let second = try #require(IncrementalJSONLReader.readLines(from: url, state: first.state))
    #expect(second.lines == ["x", "y"])
}

@Test func incrementalReaderSkipsInvalidUTF8Lines() throws {
    let url = try makeJSONLFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let invalidLine = Data([0xFF, 0xFE, 0x0A])  // invalid UTF-8 then newline
    var data = Data("good\n".utf8)
    data.append(invalidLine)
    data.append(Data("after\n".utf8))
    try data.write(to: url)

    let result = try #require(IncrementalJSONLReader.readLines(from: url, state: nil))

    #expect(result.lines == ["good", "after"])
}

@Test func incrementalReaderDeliversMalformedJSONAsRawLines() throws {
    let url = try makeJSONLFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("not-json\n{\"valid\":true}\n".utf8).write(to: url)

    let result = try #require(IncrementalJSONLReader.readLines(from: url, state: nil))

    #expect(result.lines == ["not-json", "{\"valid\":true}"])
}