import Foundation
import MetaGraphPrimitives
import MetaTrustedHeadProtocol

/// A durable journal anchored by a separately supervised trusted-head broker.
/// It deliberately wraps an unanchored local journal: production callers
/// cannot combine this adapter with the legacy same-identity head directory.
public actor BrokerBackedMutationJournal: MutationJournaling {
  private let journal: DurableMutationJournal
  private let broker: any TrustedHeadClient
  public nonisolated let namespace: String
  public nonisolated let hasTrustedHeadAnchor = true
  public nonisolated let hasBrokerBackedTrustedHeadAnchor = true

  /// The only public construction path names a concrete Unix broker client.
  public init(
    journal: DurableMutationJournal, configuration: TrustedHeadBrokerConfiguration
  ) throws {
    guard !journal.hasTrustedHeadAnchor else { throw GraphValidationError.policyDenied }
    self.journal = journal
    broker = UnixTrustedHeadBrokerClient(configuration: configuration)
    namespace = journal.namespace
  }

  /// Test-only seam. It is internal so an in-memory client cannot be supplied
  /// by package consumers as a production rollback anchor.
  init(journal: DurableMutationJournal, broker: any TrustedHeadClient) throws {
    guard !journal.hasTrustedHeadAnchor else { throw GraphValidationError.policyDenied }
    self.journal = journal
    self.broker = broker
    namespace = journal.namespace
  }

  public func prepare(_ key: MutationJournalKey, digest: String) async throws {
    try await journal.prepare(key, digest: digest)
    try await synchronize(key)
  }

  public func transition(
    _ key: MutationJournalKey, to state: MutationJournalState, receiptDigest: String?
  ) async throws {
    let before = try await requireBrokerMatch(key)
    try await journal.transition(key, to: state, receiptDigest: receiptDigest)
    let after = try await anchor(for: key)
    guard after.recordIdentity == before.recordIdentity,
      after.head.sequence == before.head.sequence + 1
    else { throw GraphValidationError.policyDenied }
    try await advanceBroker(from: before, to: after)
  }

  public func state(for key: MutationJournalKey) async throws -> MutationJournalState? {
    try await synchronize(key)
    return try await journal.state(for: key)
  }

  public func receiptStatus(for key: MutationJournalKey) async throws -> Int? {
    try await synchronize(key)
    return try await journal.receiptStatus(for: key)
  }

  public func reconcile(
    _ key: MutationJournalKey, result: MutationReconciliationState
  ) async throws -> MutationJournalState {
    let before = try await requireBrokerMatch(key)
    let state = try await journal.reconcile(key, result: result)
    let after = try await anchor(for: key)
    guard after.recordIdentity == before.recordIdentity else {
      throw GraphValidationError.policyDenied
    }
    // Pending and unavailable reconciliation results are intentionally
    // non-terminal: the durable journal retains outcomeUnknown and must not
    // manufacture a broker event. The broker head still has to prove that no
    // concurrent rollback or advance happened while reconciliation ran.
    if result == .pending || result == .unavailable {
      guard state == .outcomeUnknown, after.head == before.head else {
        throw GraphValidationError.policyDenied
      }
      return state
    }
    guard after.head.sequence == before.head.sequence + 1 else {
      throw GraphValidationError.policyDenied
    }
    try await advanceBroker(from: before, to: after)
    return state
  }

  private func anchor(for key: MutationJournalKey) async throws -> BrokerJournalAnchor {
    guard let anchor = try await journal.brokerAnchor(for: key) else {
      throw GraphValidationError.policyDenied
    }
    return anchor
  }

  private func requireBrokerMatch(_ key: MutationJournalKey) async throws -> BrokerJournalAnchor {
    let current = try await anchor(for: key)
    guard
      try await broker.readHead(namespace: namespace, recordIdentity: current.recordIdentity)
        == current.head
    else { throw GraphValidationError.policyDenied }
    return current
  }

  /// A crash after an atomic journal replace may leave the independent broker
  /// exactly one event behind. Recovery may perform only this proven one-step
  /// CAS; all other missing, stale, or split-brain heads are denied.
  private func synchronize(_ key: MutationJournalKey) async throws {
    let current = try await anchor(for: key)
    let anchored = try await broker.readHead(
      namespace: namespace, recordIdentity: current.recordIdentity)
    if anchored == current.head { return }
    guard
      (anchored == nil && current.head.sequence == 1)
        || (anchored?.sequence == current.head.sequence - 1)
    else { throw GraphValidationError.policyDenied }
    guard
      try await broker.compareAndSetHead(
        namespace: namespace, recordIdentity: current.recordIdentity, expected: anchored,
        proposed: current.head)
    else { throw GraphValidationError.policyDenied }
  }

  private func advanceBroker(from previous: BrokerJournalAnchor, to current: BrokerJournalAnchor)
    async throws
  {
    guard
      try await broker.compareAndSetHead(
        namespace: namespace, recordIdentity: current.recordIdentity, expected: previous.head,
        proposed: current.head)
    else { throw GraphValidationError.policyDenied }
  }
}
