import Foundation
import Testing
@testable import VibeBarCore

@Test func energyDiagnosticsCountsAndResetsOperations() {
    let diagnostics = EnergyDiagnostics()
    diagnostics.record(.processSnapshot)
    diagnostics.record(.processSnapshot)

    #expect(diagnostics.count(for: .processSnapshot) == 2)
    diagnostics.reset()
    #expect(diagnostics.count(for: .processSnapshot) == 0)
}

@Test func energyDiagnosticsRecordsDistinctOperationsIndependently() {
    let diagnostics = EnergyDiagnostics()
    diagnostics.record(.modelRefresh)
    diagnostics.record(.modelRefresh)
    diagnostics.record(.cwdLookup)

    #expect(diagnostics.count(for: .modelRefresh) == 2)
    #expect(diagnostics.count(for: .cwdLookup) == 1)
    #expect(diagnostics.count(for: .fullscreenCheck) == 0)
}