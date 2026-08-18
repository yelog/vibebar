import Foundation
import Testing
@testable import VibeBarApp

@Test func eventReasonUses30SecondSnapshotTTL() {
    let policy = ProcessSnapshotPolicyResolver.policy(for: .event, hasSessions: true)
    #expect(policy.ttl == 30)
}

@Test func periodicReasonUses30SecondTTLWithSessions() {
    let policy = ProcessSnapshotPolicyResolver.policy(for: .periodic, hasSessions: true)
    #expect(policy.ttl == 30)
}

@Test func periodicReasonUses60SecondTTLWithoutSessions() {
    let policy = ProcessSnapshotPolicyResolver.policy(for: .periodic, hasSessions: false)
    #expect(policy.ttl == 60)
}

@Test func manualReasonRequestsFreshSnapshot() {
    let policy = ProcessSnapshotPolicyResolver.policy(for: .manual, hasSessions: true)
    #expect(policy.ttl == 0)
}

@Test func wakeReasonRequestsFreshSnapshot() {
    let policy = ProcessSnapshotPolicyResolver.policy(for: .wake, hasSessions: true)
    #expect(policy.ttl == 0)
}