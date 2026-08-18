import Foundation
import Testing
@testable import VibeBarCore

@Suite("Process Execution Tests")
struct DetectorSupportProcessTests {
    @Test func processOutputReturnsAfterSuccessfulCommand() {
        let output = DetectorSupport.runProcessOutput(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf ready"],
            timeout: 1
        )
        #expect(String(data: output ?? Data(), encoding: .utf8) == "ready")
    }

    @Test func processOutputReturnsLargeOutput() {
        let output = DetectorSupport.runProcessOutput(
            executablePath: "/bin/sh",
            arguments: ["-c", "yes x | head -c 200000"],
            timeout: 2
        )
        #expect(output?.count == 200000)
    }

    @Test func processTimeoutReturnsNilAndRemainsBounded() {
        let startedAt = Date()
        for _ in 0..<40 {
            let output = DetectorSupport.runProcessOutput(
                executablePath: "/bin/sh",
                arguments: ["-c", "sleep 5"],
                timeout: 0.02
            )
            #expect(output == nil)
        }
        #expect(Date().timeIntervalSince(startedAt) < 12)
    }

    @Test func processErrorOutputDoesNotBlockReader() {
        let output = DetectorSupport.runProcessOutput(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo oops >&2; printf out"],
            timeout: 1
        )
        #expect(String(data: output ?? Data(), encoding: .utf8) == "out")
    }
}
