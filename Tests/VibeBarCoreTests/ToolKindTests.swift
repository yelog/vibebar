import Testing
@testable import VibeBarCore

@Test func piCLIArgumentAliases() {
    #expect(ToolKind.fromCLIArgument("pi") == .pi)
    #expect(ToolKind.fromCLIArgument("PI") == .pi)
    #expect(ToolKind.fromCLIArgument("omp") == .ohMyPi)
    #expect(ToolKind.fromCLIArgument("oh-my-pi") == .ohMyPi)
    #expect(ToolKind.fromCLIArgument("oh_my_pi") == .ohMyPi)
    #expect(ToolKind.fromCLIArgument("omp") != .pi)
    #expect(ToolKind.fromCLIArgument("pi") != .ohMyPi)
}

@Test func piDirectProcessDetection() {
    #expect(ToolKind.detect(command: "/opt/homebrew/bin/pi", args: "pi") == .pi)
    #expect(ToolKind.detect(command: "/usr/local/bin/omp", args: "omp") == .ohMyPi)
    #expect(ToolKind.detect(command: "pi", args: "") == .pi)
    #expect(ToolKind.detect(command: "omp", args: "") == .ohMyPi)
}

@Test func piRuntimeBasedInvocationDetection() {
    #expect(ToolKind.detect(command: "/usr/bin/env", args: "pi --model x") == .pi)
    #expect(ToolKind.detect(command: "/usr/bin/env", args: "omp --profile work") == .ohMyPi)
    #expect(ToolKind.detect(command: "bun", args: "run pi") == .pi)
    #expect(ToolKind.detect(command: "bun", args: "run omp") == .ohMyPi)
}

@Test func piDetectionDoesNotMatchUnrelatedArguments() {
    #expect(ToolKind.detect(command: "/usr/bin/env", args: "npm run build") == nil)
    #expect(ToolKind.detect(command: "/usr/bin/env", args: "python -m pip install") == nil)
    #expect(ToolKind.detect(command: "/usr/bin/env", args: "compiler --pi") == nil)
    #expect(ToolKind.detect(command: "python", args: "pi.py") == nil)
    #expect(ToolKind.detect(command: "python", args: "omp.py") == nil)
}

@Test func piDisplayMetadata() {
    #expect(ToolKind.pi.displayName == "Pi")
    #expect(ToolKind.pi.shortDisplayName == "Pi")
    #expect(ToolKind.pi.executable == "pi")
    #expect(ToolKind.pi.iconResourceName == "pi")
    #expect(ToolKind.ohMyPi.displayName == "Oh My Pi")
    #expect(ToolKind.ohMyPi.shortDisplayName == "OMP")
    #expect(ToolKind.ohMyPi.executable == "omp")
    #expect(ToolKind.ohMyPi.iconResourceName == "ohMyPi")
}

@Test func piAndOhMyPiAreDistinctCases() {
    #expect(ToolKind.pi.rawValue == "pi")
    #expect(ToolKind.ohMyPi.rawValue == "oh-my-pi")
    #expect(ToolKind.pi != ToolKind.ohMyPi)
    #expect(ToolKind.allCases.contains(.pi))
    #expect(ToolKind.allCases.contains(.ohMyPi))
}
