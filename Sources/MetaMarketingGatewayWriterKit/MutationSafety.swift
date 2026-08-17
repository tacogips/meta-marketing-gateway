import Darwin
import Foundation
import MetaGraphPrimitives
import MetaTrustedHeadProtocol

public enum MutationConfirmationClass: String, Sendable, Codable {
  case standard
  case highRisk
  case destructive
  case spendAffecting
}

public enum MutationAssetClassification: String, Sendable, Codable {
  case verifiedNonBillableTest
  case live
}

/// Provider evidence, not caller labels, decides whether an asset is eligible.
public struct VerifiedTestAssetEvidence: Sendable, Equatable, Codable {
  public let assetID: String
  public let providerVerifiedAt: Date
  public let nonBillable: Bool
  public init(assetID: String, providerVerifiedAt: Date, nonBillable: Bool) throws {
    guard !assetID.isEmpty, assetID.utf8.count <= 256 else {
      throw GraphValidationError.invalidIdentifier
    }
    self.assetID = assetID
    self.providerVerifiedAt = providerVerifiedAt
    self.nonBillable = nonBillable
  }
  public func classification(now: Date, maximumAge: TimeInterval = 300)
    -> MutationAssetClassification
  {
    guard nonBillable, now.timeIntervalSince(providerVerifiedAt) >= 0,
      now.timeIntervalSince(providerVerifiedAt) <= maximumAge
    else { return .live }
    return .verifiedNonBillableTest
  }
}

public struct MutationDescriptor: Sendable, Equatable, Codable {
  public let operationID: String
  public let method: GraphMethod
  public let pathPrefix: String
  public let risk: MutationRisk
  public let confirmation: MutationConfirmationClass
  public let mayAffectSpend: Bool
  public let permitsSafeRetry: Bool

  public init(
    operationID: String, method: GraphMethod, pathPrefix: String, risk: MutationRisk,
    confirmation: MutationConfirmationClass, mayAffectSpend: Bool = false,
    permitsSafeRetry: Bool = false
  ) throws {
    guard operationID.wholeMatch(of: /meta\.[a-z0-9.-]{3,127}/) != nil,
      method == .post, !pathPrefix.isEmpty, !pathPrefix.contains("://"), !pathPrefix.hasPrefix("/"),
      risk != .denied
    else { throw GraphValidationError.policyDenied }
    if mayAffectSpend {
      guard
        (risk == .highImpact && confirmation == .spendAffecting)
          || (risk == .destructive && confirmation == .destructive)
      else {
        throw GraphValidationError.policyDenied
      }
    }
    self.operationID = operationID
    self.method = method
    self.pathPrefix = pathPrefix
    self.risk = risk
    self.confirmation = confirmation
    self.mayAffectSpend = mayAffectSpend
    self.permitsSafeRetry = permitsSafeRetry
  }
}

/// Non-secret identity returned by an authenticated provider identity endpoint.
/// Callers cannot use an arbitrary identifier as evidence: production writers
/// require a verifier implementation and match this value at apply time.
public struct ProviderPrincipalEvidence: Sendable, Equatable, Codable {
  public let appID: String
  public let actorID: String
  public let verifiedAt: Date

  public init(appID: String, actorID: String, verifiedAt: Date) throws {
    guard
      [appID, actorID].allSatisfy({
        !$0.isEmpty && $0.utf8.count <= 256
          && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
      })
    else { throw GraphValidationError.invalidIdentifier }
    self.appID = appID
    self.actorID = actorID
    self.verifiedAt = verifiedAt
  }

  public var journalPrincipal: String { "\(appID):\(actorID)" }

  /// Verification time is evidence freshness, not part of the authenticated
  /// identity. A refreshed credential for the same app/actor must remain valid.
  public func matchesIdentity(_ other: ProviderPrincipalEvidence) -> Bool {
    appID == other.appID && actorID == other.actorID
  }

  public func isFresh(now: Date, maximumAge: TimeInterval = 300) -> Bool {
    let age = now.timeIntervalSince(verifiedAt)
    return age >= 0 && age <= maximumAge
  }
}

public protocol MutationPrincipalVerifying: Sendable {
  func verify(credential: GraphCredential) async throws -> ProviderPrincipalEvidence
}

public protocol MutationAssetVerifying: Sendable {
  func verify(assetID: String, credential: GraphCredential) async throws
    -> VerifiedTestAssetEvidence
}

public enum MutationReconciliationState: String, Sendable, Codable {
  case verifiedEffect
  case verifiedNoEffect
  case pending
  case unavailable
}

/// Internal evidence for a deliberately out-of-band trusted-head recovery.
/// It is intentionally unavailable to ordinary clients and mutation callers;
/// a privileged composition layer must obtain it from independently protected
/// recovery evidence before invoking the internal recovery operation.
struct TrustedHeadRecoveryExpectation: Sendable, Equatable {
  let recordIdentity: String
  let firstRetainedSequence: UInt64
  let previousRetainedHash: String?
  let sequence: UInt64
  let hash: String
  let anchoredFirstRetainedSequence: UInt64
  let anchoredPreviousRetainedHash: String?
  let anchoredSequence: UInt64
  let anchoredHash: String

  init(
    recordIdentity: String, firstRetainedSequence: UInt64, previousRetainedHash: String?,
    sequence: UInt64, hash: String, anchoredFirstRetainedSequence: UInt64,
    anchoredPreviousRetainedHash: String?, anchoredSequence: UInt64, anchoredHash: String
  ) throws {
    guard Self.isDigest(recordIdentity), Self.isDigest(hash), Self.isDigest(anchoredHash),
      Self.isValidBoundary(
        firstRetainedSequence, previousRetainedHash, finalSequence: sequence),
      Self.isValidBoundary(
        anchoredFirstRetainedSequence, anchoredPreviousRetainedHash,
        finalSequence: anchoredSequence)
    else {
      throw GraphValidationError.policyDenied
    }
    self.recordIdentity = recordIdentity
    self.firstRetainedSequence = firstRetainedSequence
    self.previousRetainedHash = previousRetainedHash
    self.sequence = sequence
    self.hash = hash
    self.anchoredFirstRetainedSequence = anchoredFirstRetainedSequence
    self.anchoredPreviousRetainedHash = anchoredPreviousRetainedHash
    self.anchoredSequence = anchoredSequence
    self.anchoredHash = anchoredHash
  }

  private static func isDigest(_ value: String) -> Bool {
    value.wholeMatch(of: /[0-9a-f]{64}/) != nil
  }

  private static func isValidBoundary(
    _ firstRetainedSequence: UInt64, _ previousRetainedHash: String?, finalSequence: UInt64
  ) -> Bool {
    guard firstRetainedSequence > 0, firstRetainedSequence <= finalSequence else { return false }
    if firstRetainedSequence == 1 { return previousRetainedHash == nil }
    return previousRetainedHash.map(isDigest) ?? false
  }
}

public protocol MutationReconciling: Sendable {
  func reconcile(
    descriptor: MutationDescriptor, path: GraphPath, credential: GraphCredential
  ) async throws -> MutationReconciliationState
}

public struct MutationApplyAuthorization: Sendable {
  public let descriptor: MutationDescriptor
  public let journalKey: MutationJournalKey
  public let expectedPrincipal: ProviderPrincipalEvidence
  public let assetID: String
  public let requestedLiabilityCents: Int

  public init(
    descriptor: MutationDescriptor, journalKey: MutationJournalKey,
    expectedPrincipal: ProviderPrincipalEvidence, assetID: String, requestedLiabilityCents: Int
  ) throws {
    guard let pathAssetID = Self.assetID(boundBy: descriptor.pathPrefix),
      assetID == pathAssetID,
      journalKey.principal == expectedPrincipal.journalPrincipal,
      journalKey.operationID == descriptor.operationID,
      journalKey.target == assetID, !assetID.isEmpty, requestedLiabilityCents >= 0
    else { throw GraphValidationError.policyDenied }
    self.descriptor = descriptor
    self.journalKey = journalKey
    self.expectedPrincipal = expectedPrincipal
    self.assetID = assetID
    self.requestedLiabilityCents = requestedLiabilityCents
  }

  /// The ad account authorized by provider evidence must be the same canonical
  /// account at the beginning of the descriptor path. This rules out applying
  /// a test account's evidence to a different account's mutation path.
  private static func assetID(boundBy pathPrefix: String) -> String? {
    guard let first = pathPrefix.split(separator: "/", maxSplits: 1).first,
      String(first).wholeMatch(of: /act_[0-9]+/) != nil
    else { return nil }
    return String(first)
  }
}

public struct MutationApplyDependencies: Sendable {
  public let authorization: MutationApplyAuthorization
  public let journal: any MutationJournaling
  public let principalVerifier: any MutationPrincipalVerifying
  public let assetVerifier: any MutationAssetVerifying
  public let reconciler: (any MutationReconciling)?

  /// Public callers cannot construct executable writer dependencies until the
  /// broker-backed production composition exists. This initializer is visible
  /// only to the package test target through `@testable import`.
  init(
    authorization: MutationApplyAuthorization, journal: any MutationJournaling,
    principalVerifier: any MutationPrincipalVerifying, assetVerifier: any MutationAssetVerifying,
    reconciler: (any MutationReconciling)? = nil
  ) throws {
    try self.init(
      authorization: authorization, journal: journal, principalVerifier: principalVerifier,
      assetVerifier: assetVerifier, reconciler: reconciler, allowUnanchoredForTesting: false)
  }

  /// This initializer is deliberately internal so only the test target, via
  /// `@testable import`, can construct an offline fake without rollback
  /// anchoring. Production clients must use the public initializer above.
  init(
    authorization: MutationApplyAuthorization, journal: any MutationJournaling,
    principalVerifier: any MutationPrincipalVerifying, assetVerifier: any MutationAssetVerifying,
    reconciler: (any MutationReconciling)? = nil, allowUnanchoredForTesting: Bool
  ) throws {
    guard authorization.journalKey.namespace == journal.namespace,
      allowUnanchoredForTesting || journal.hasBrokerBackedTrustedHeadAnchor
    else { throw GraphValidationError.policyDenied }
    self.authorization = authorization
    self.journal = journal
    self.principalVerifier = principalVerifier
    self.assetVerifier = assetVerifier
    self.reconciler = reconciler
  }
}

public enum MutationPolicy {
  /// Standard risk is available only through this finite, library-owned
  /// operation set. All generic and unknown identities remain conservative.
  private static let standardTypedOperationIDs: Set<String> = ["meta.ad-account.rename"]
  private static let immutableDeniedTerms = [
    "access", "permission", "ownership", "billing", "payment", "funding", "token", "credential",
    "audience", "customaudience", "upload",
  ]

  private static let highImpactTerms = [
    "status", "effective_status", "delivery_status", "activate", "active", "budget",
    "daily_budget", "lifetime_budget", "spend", "bid", "bid_amount", "rule", "targeting",
    "schedule", "start_time", "end_time",
  ]
  private static let spendTerms = [
    "budget", "daily_budget", "lifetime_budget", "spend", "bid", "bid_amount",
  ]
  private static let servingTerms = [
    "status", "effective_status", "delivery_status", "activate", "active",
  ]

  /// The result is derived from exact canonical request material. Descriptor
  /// metadata is deliberately not an input: it is only a claim checked by the
  /// writer after this policy has made the conservative decision.
  public struct Result: Sendable, Equatable {
    public let operationID: String
    public let risk: MutationRisk
    public let confirmation: MutationConfirmationClass
    public let mayAffectSpend: Bool
    public let requestedLiabilityCents: Int
    public let denialReasons: [String]
    public let digest: String

    fileprivate init(
      operationID: String, risk: MutationRisk, confirmation: MutationConfirmationClass,
      mayAffectSpend: Bool,
      requestedLiabilityCents: Int = 0,
      denialReasons: [String], material: String
    ) {
      self.operationID = operationID
      self.risk = risk
      self.confirmation = confirmation
      self.mayAffectSpend = mayAffectSpend
      self.requestedLiabilityCents = requestedLiabilityCents
      self.denialReasons = denialReasons
      digest = MetaGraphWriter.digest(Data(material.utf8))
    }
  }

  public static func classify(
    _ request: GraphRequest
  ) throws -> Result {
    try classify(
      method: request.method, path: request.path, query: request.query, body: request.body,
      bodyMediaType: request.bodyMediaType, operationID: request.operationID)
  }

  public static func classify(
    method: GraphMethod, path: GraphPath, query: GraphQuery, body: Data?,
    bodyMediaType: GraphBodyMediaType? = nil, operationID: String? = nil
  ) throws -> Result {
    guard (body == nil) == (bodyMediaType == nil),
      Set(query.items.map { $0.0.lowercased() }).count == query.items.count
    else { throw GraphValidationError.policyDenied }
    let pathTerms = path.segments.flatMap { terms(in: $0) }
    let queryTerms = query.items.flatMap { terms(in: $0.0) + terms(in: $0.1) }
    let bodyTerms: [String] =
      try body.map { bytes in
        guard bodyMediaType == .json else { throw GraphValidationError.policyDenied }
        return try jsonTerms(bytes)
      } ?? []
    let allTerms = pathTerms + queryTerms + bodyTerms
    let resolvedOperationID = operationID ?? genericOperationID(for: method)
    guard resolvedOperationID.wholeMatch(of: /meta\.[a-z0-9.-]{3,127}/) != nil else {
      throw GraphValidationError.policyDenied
    }
    let canonical = [
      resolvedOperationID,
      method.rawValue,
      path.description,
      query.encoded(),
      MetaGraphWriter.digest(body ?? Data()), bodyMediaType?.rawValue ?? "",
      allTerms.sorted().joined(separator: ","),
    ].joined(separator: "|")

    if allTerms.contains(where: { immutableDeniedTerms.contains($0) }) {
      return Result(
        operationID: resolvedOperationID, risk: .denied, confirmation: .highRisk,
        mayAffectSpend: false,
        denialReasons: ["immutable-denied mutation category"], material: canonical)
    }
    if standardTypedOperationIDs.contains(resolvedOperationID) {
      guard isStandardAdAccountRename(method: method, path: path, query: query, body: body) else {
        return Result(
          operationID: resolvedOperationID, risk: .denied, confirmation: .highRisk,
          mayAffectSpend: false,
          denialReasons: ["typed operation input is not allowlisted"], material: canonical)
      }
      return Result(
        operationID: resolvedOperationID, risk: .standard, confirmation: .standard,
        mayAffectSpend: false, denialReasons: [], material: canonical)
    }
    guard resolvedOperationID == genericOperationID(for: method) else {
      return Result(
        operationID: resolvedOperationID, risk: .denied, confirmation: .highRisk,
        mayAffectSpend: false, denialReasons: ["unknown typed operation"], material: canonical)
    }
    if allTerms.contains("delete") || allTerms.contains("archive") {
      return Result(
        operationID: resolvedOperationID, risk: .denied, confirmation: .destructive,
        mayAffectSpend: false,
        denialReasons: ["delete-equivalent POST aliases belong to Deleter"], material: canonical)
    }
    // Generic writes are intentionally never standard. This catches both
    // unknown fields and an otherwise innocuous-looking request before it can
    // inherit a caller-supplied standard descriptor.
    let hasExplicitSpend = allTerms.contains(where: { spendTerms.contains($0) })
    let mayAffectSpend =
      hasExplicitSpend
      || allTerms.contains(where: { servingTerms.contains($0) })
    let liability = try requestedLiabilityCents(query: query, body: body)
    return Result(
      operationID: resolvedOperationID, risk: .highImpact,
      confirmation: mayAffectSpend ? .spendAffecting : .highRisk,
      mayAffectSpend: mayAffectSpend,
      requestedLiabilityCents: liability,
      denialReasons: [], material: canonical)
  }

  public static func generic(method: GraphMethod, path: GraphPath) -> MutationDescriptor? {
    guard
      let result = try? classify(
        method: method, path: path, query: try GraphQuery(), body: nil,
        operationID: genericOperationID(for: method)),
      result.risk != .denied
    else { return nil }
    return try? MutationDescriptor(
      operationID: result.operationID,
      method: method, pathPrefix: path.description, risk: result.risk,
      confirmation: result.confirmation, mayAffectSpend: result.mayAffectSpend)
  }

  private static func terms(in value: String) -> [String] {
    value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
  }

  private static func genericOperationID(for method: GraphMethod) -> String {
    "meta.generic.write"
  }

  private static func isStandardAdAccountRename(
    method: GraphMethod, path: GraphPath, query: GraphQuery, body: Data?
  ) -> Bool {
    guard
      method == .post,
      body == nil,
      path.segments.count == 2,
      path.segments[0].wholeMatch(of: /act_[0-9]+/) != nil,
      path.segments[1] == "name",
      query.items.count == 1,
      query.items[0].0 == "name"
    else { return false }
    let value = query.items[0].1
    return !value.isEmpty && value.utf8.count <= 256
      && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
  }

  private static func jsonTerms(_ body: Data) throws -> [String] {
    guard !body.isEmpty else { return [] }
    var duplicateValidator = JSONDuplicateFieldValidator(body)
    try duplicateValidator.validate()
    let decoded: Any
    do {
      decoded = try JSONSerialization.jsonObject(with: body, options: [])
    } catch {
      throw GraphValidationError.policyDenied
    }
    var result: [String] = []
    func visit(_ value: Any, depth: Int) throws {
      guard depth <= 8, result.count <= 256 else { throw GraphValidationError.policyDenied }
      if let object = value as? [String: Any] {
        for (key, nested) in object {
          result.append(contentsOf: terms(in: key))
          try visit(nested, depth: depth + 1)
        }
      } else if let list = value as? [Any] {
        for nested in list { try visit(nested, depth: depth + 1) }
      } else if let string = value as? String {
        result.append(contentsOf: terms(in: string))
      }
    }
    try visit(decoded, depth: 0)
    return result
  }

  /// A declared money-like field has an unambiguous integer-cents value only
  /// when it is a non-negative JSON number/string or duplicate-free query
  /// parameter. Unknown shapes fail closed instead of accepting a caller's
  /// lower liability claim.
  private static func requestedLiabilityCents(query: GraphQuery, body: Data?) throws -> Int {
    var total = 0
    func add(_ raw: String) throws {
      guard let value = Int(raw), value >= 0, total <= Int.max - value else {
        throw GraphValidationError.policyDenied
      }
      total += value
    }
    for (key, value) in query.items
    where terms(in: key).contains(where: { spendTerms.contains($0) }) {
      try add(value)
    }
    guard let body else { return total }
    let decoded: Any
    do { decoded = try JSONSerialization.jsonObject(with: body) } catch {
      throw GraphValidationError.policyDenied
    }
    func visit(_ value: Any, field: String? = nil, depth: Int = 0) throws {
      guard depth <= 8 else { throw GraphValidationError.policyDenied }
      if let object = value as? [String: Any] {
        for (key, nested) in object { try visit(nested, field: key, depth: depth + 1) }
      } else if let array = value as? [Any] {
        for nested in array { try visit(nested, field: field, depth: depth + 1) }
      } else if let field, terms(in: field).contains(where: { spendTerms.contains($0) }) {
        if let value = value as? String {
          try add(value)
        } else if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
          try add(value.stringValue)
        } else {
          throw GraphValidationError.policyDenied
        }
      }
    }
    try visit(decoded)
    return total
  }
}

private struct JSONDuplicateFieldValidator {
  private let bytes: [UInt8]
  private var index = 0

  init(_ data: Data) { bytes = Array(data) }

  mutating func validate() throws {
    try value(depth: 0)
    whitespace()
    guard index == bytes.count else { throw GraphValidationError.policyDenied }
  }

  private mutating func whitespace() {
    while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
  }

  private mutating func value(depth: Int) throws {
    guard depth <= 8 else { throw GraphValidationError.policyDenied }
    whitespace()
    guard index < bytes.count else { throw GraphValidationError.policyDenied }
    switch bytes[index] {
    case 123: try object(depth: depth + 1)
    case 91: try array(depth: depth + 1)
    case 34: _ = try string()
    default:
      let start = index
      while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
      guard index > start,
        (try? JSONSerialization.jsonObject(
          with: Data(bytes[start..<index]), options: [.fragmentsAllowed])) != nil
      else { throw GraphValidationError.policyDenied }
    }
  }

  private mutating func object(depth: Int) throws {
    index += 1
    whitespace()
    if index < bytes.count, bytes[index] == 125 {
      index += 1
      return
    }
    var names = Set<String>()
    while true {
      whitespace()
      let name = try string()
      guard names.insert(name).inserted else { throw GraphValidationError.policyDenied }
      whitespace()
      guard index < bytes.count, bytes[index] == 58 else { throw GraphValidationError.policyDenied }
      index += 1
      try value(depth: depth)
      whitespace()
      guard index < bytes.count else { throw GraphValidationError.policyDenied }
      if bytes[index] == 125 {
        index += 1
        return
      }
      guard bytes[index] == 44 else { throw GraphValidationError.policyDenied }
      index += 1
    }
  }

  private mutating func array(depth: Int) throws {
    index += 1
    whitespace()
    if index < bytes.count, bytes[index] == 93 {
      index += 1
      return
    }
    while true {
      try value(depth: depth)
      whitespace()
      guard index < bytes.count else { throw GraphValidationError.policyDenied }
      if bytes[index] == 93 {
        index += 1
        return
      }
      guard bytes[index] == 44 else { throw GraphValidationError.policyDenied }
      index += 1
    }
  }

  private mutating func string() throws -> String {
    whitespace()
    let start = index
    guard index < bytes.count, bytes[index] == 34 else { throw GraphValidationError.policyDenied }
    index += 1
    while index < bytes.count {
      if bytes[index] == 92 {
        index += 2
        continue
      }
      if bytes[index] == 34 {
        index += 1
        break
      }
      guard bytes[index] >= 32 else { throw GraphValidationError.policyDenied }
      index += 1
    }
    guard index <= bytes.count,
      let value = try? JSONSerialization.jsonObject(
        with: Data(bytes[start..<index]), options: [.fragmentsAllowed]) as? String
    else { throw GraphValidationError.policyDenied }
    return value
  }
}

/// V1 has an explicit USD 0 authorization ceiling. This is distinct from, and
/// cannot predict, provider invoicing or changes made by other actors.
public enum SpendSafety {
  public static func authorize(
    classification: MutationAssetClassification, requestedLiabilityCents: Int,
    mayAffectSpend: Bool
  ) throws {
    guard requestedLiabilityCents >= 0 else { throw GraphValidationError.policyDenied }
    guard classification == .verifiedNonBillableTest else {
      throw GraphValidationError.policyDenied
    }
    guard !mayAffectSpend || requestedLiabilityCents == 0 else {
      throw GraphValidationError.policyDenied
    }
    guard requestedLiabilityCents == 0 else { throw GraphValidationError.policyDenied }
  }
}

public enum MutationJournalState: String, Sendable, Codable {
  case prepared, inFlight, succeeded, failedSafeToRetry, outcomeUnknown
}

/// Test-only durability checkpoints. A production journal leaves this unset;
/// the seam lets deterministic tests model a process loss on either side of an
/// atomic record replacement without storing a crash marker in the journal.
public enum MutationJournalCheckpoint: Sendable {
  case beforeReplace
  case afterReplace
}

public struct MutationJournalKey: Sendable, Hashable, Codable {
  public let namespace: String
  public let principal: String
  public let target: String
  public let operationID: String
  public let idempotencyKey: String
  public init(
    namespace: String, principal: String, target: String, operationID: String,
    idempotencyKey: String
  )
    throws
  {
    guard
      [namespace, principal, target, operationID, idempotencyKey].allSatisfy({
        !$0.isEmpty && $0.utf8.count <= 256
      })
    else { throw GraphValidationError.invalidRequest }
    self.namespace = namespace
    self.principal = principal
    self.target = target
    self.operationID = operationID
    self.idempotencyKey = idempotencyKey
  }
}

/// The executable writer depends on this narrow asynchronous state contract.
/// The legacy directory-backed journal and the broker-backed adapter are
/// distinct implementations; only the latter may represent production
/// rollback anchoring once a closed composition root is installed.
public protocol MutationJournaling: Sendable {
  var namespace: String { get }
  var hasTrustedHeadAnchor: Bool { get }
  var hasBrokerBackedTrustedHeadAnchor: Bool { get }
  func prepare(_ key: MutationJournalKey, digest: String) async throws
  func transition(
    _ key: MutationJournalKey, to state: MutationJournalState, receiptDigest: String?
  ) async throws
  func state(for key: MutationJournalKey) async throws -> MutationJournalState?
  func receiptStatus(for key: MutationJournalKey) async throws -> Int?
  func reconcile(_ key: MutationJournalKey, result: MutationReconciliationState) async throws
    -> MutationJournalState
}

extension MutationJournaling {
  public func transition(_ key: MutationJournalKey, to state: MutationJournalState) async throws {
    try await transition(key, to: state, receiptDigest: nil)
  }
}

struct BrokerJournalAnchor: Sendable, Equatable {
  let recordIdentity: String
  let head: TrustedHead
}

/// Process-local state machine used by deterministic fakes. Production apply
/// remains fail-closed until a separately reviewed durable journal backend is
/// configured; this type never stores request bodies or credentials.
public actor MutationJournal {
  private var entries:
    [MutationJournalKey: (digest: String, state: MutationJournalState, receiptDigest: String?)] =
      [:]
  public init() {}
  public func prepare(_ key: MutationJournalKey, digest: String) throws {
    if let existing = entries[key] {
      guard existing.digest == digest, existing.state == .succeeded else {
        throw GraphValidationError.policyDenied
      }
      return
    }
    entries[key] = (digest, .prepared, nil)
  }
  public func transition(
    _ key: MutationJournalKey, to state: MutationJournalState, receiptDigest: String? = nil
  ) throws {
    guard let entry = entries[key] else { throw GraphValidationError.policyDenied }
    let allowed: Set<MutationJournalState> =
      switch entry.state {
      case .prepared: [.inFlight]
      case .inFlight: [.succeeded, .failedSafeToRetry, .outcomeUnknown]
      case .failedSafeToRetry: [.inFlight]
      case .succeeded, .outcomeUnknown: []
      }
    guard allowed.contains(state) else { throw GraphValidationError.policyDenied }
    entries[key] = (entry.digest, state, receiptDigest ?? entry.receiptDigest)
  }
  public func state(for key: MutationJournalKey) -> MutationJournalState? { entries[key]?.state }
}

/// An owner-only, process-locked journal backend. Records retain their key and
/// digest tombstone permanently; request bodies and credentials are never
/// written. Writer apply remains disabled until principal/asset/reconciliation
/// dependencies can bind this backend.
public actor DurableMutationJournal: MutationJournaling {
  private static let schemaVersion = 3

  private struct NamespaceMarker: Codable {
    let schema: Int
    let value: String
  }

  private struct RetiredNamespace: Codable {
    let replacementNamespace: String
  }

  private struct Event: Codable {
    let schema: Int
    let sequence: UInt64
    let state: MutationJournalState
    let receiptDigest: String?
    let previousHash: String?
    let hash: String
  }

  private struct Entry: Codable {
    let schema: Int
    let key: MutationJournalKey
    let digest: String
    let recordIdentity: String
    let firstRetainedSequence: UInt64
    let previousRetainedHash: String?
    let events: [Event]
  }

  /// A trusted head belongs in a separately protected directory. It makes a
  /// rollback to an older, otherwise valid journal file detectable. The
  /// journal deliberately cannot claim protection if the anchor directory is
  /// the same directory as the mutable records.
  private struct TrustedHead: Codable {
    let schema: Int
    let namespace: String
    let recordName: String
    let recordIdentity: String
    let firstRetainedSequence: UInt64
    let previousRetainedHash: String?
    let sequence: UInt64
    let hash: String
  }

  private let directory: URL
  private let trustedHeadsDirectory: URL?
  private let checkpoint: (@Sendable (MutationJournalCheckpoint) throws -> Void)?
  private let lockDescriptor: Int32
  /// Stable, persisted identity for this physical journal. It is intentionally
  /// independent of a caller-selected directory name and must be carried by
  /// every idempotency key and executable plan.
  public nonisolated let namespace: String
  public nonisolated let hasTrustedHeadAnchor: Bool
  public nonisolated let hasBrokerBackedTrustedHeadAnchor = false

  /// Namespace creation is an explicit administrative operation. Apply code may
  /// open an existing namespace but cannot create one opportunistically.
  public static func createNamespace(at directory: URL, namespace: String = UUID().uuidString)
    throws
  {
    guard !FileManager.default.fileExists(atPath: directory.path),
      !namespace.isEmpty, namespace.utf8.count <= 256
    else { throw GraphValidationError.policyDenied }
    try FileManager.default.createDirectory(
      at: directory.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    guard Self.isSecureDirectory(directory.deletingLastPathComponent()) else {
      throw GraphValidationError.policyDenied
    }
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    try SecureFile.syncDirectory(containing: directory)
    try SecureFile.writeNew(
      JSONEncoder().encode(NamespaceMarker(schema: schemaVersion, value: namespace)),
      to: directory.appendingPathComponent(".namespace"))
    try SecureFile.syncDirectory(containing: directory)
  }

  /// Create the independent, owner-only anchor directory used for rollback
  /// detection. It must be backed up and retained separately from the journal.
  public static func createTrustedHeadStore(at directory: URL) throws {
    try createNamespace(at: directory)
  }

  public init(
    directory: URL, trustedHeadsDirectory: URL? = nil,
    checkpoint: (@Sendable (MutationJournalCheckpoint) throws -> Void)? = nil
  ) throws {
    guard Self.isSecureDirectory(directory) else { throw GraphValidationError.policyDenied }
    let markerURL = directory.appendingPathComponent(".namespace")
    let marker = try SecureFile.read(NamespaceMarker.self, from: markerURL)
    guard marker.schema == Self.schemaVersion, !marker.value.isEmpty,
      marker.value.utf8.count <= 256,
      !FileManager.default.fileExists(atPath: directory.appendingPathComponent(".retired").path)
    else { throw GraphValidationError.policyDenied }
    if let trustedHeadsDirectory {
      guard trustedHeadsDirectory.standardizedFileURL != directory.standardizedFileURL,
        Self.isSecureDirectory(trustedHeadsDirectory)
      else { throw GraphValidationError.policyDenied }
    }
    let lock = directory.appendingPathComponent(".lock")
    lockDescriptor = open(lock.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard lockDescriptor >= 0 else { throw GraphValidationError.policyDenied }
    self.directory = directory
    self.trustedHeadsDirectory = trustedHeadsDirectory
    self.checkpoint = checkpoint
    self.namespace = marker.value
    self.hasTrustedHeadAnchor = trustedHeadsDirectory != nil
  }

  deinit { close(lockDescriptor) }

  public func prepare(_ key: MutationJournalKey, digest: String) throws {
    guard Self.isDigest(digest) else { throw GraphValidationError.policyDenied }
    try withLock {
      try validatePhysicalNamespace()
      try validateNamespace(key)
      try ensureActive()
      let url = recordURL(for: key)
      if FileManager.default.fileExists(atPath: url.path) {
        let entry = try SecureFile.read(Entry.self, from: url)
        try validate(entry, recordURL: url)
        try validateTrustedHead(entry, recordURL: url)
        guard entry.key == key, entry.digest == digest,
          [.prepared, .succeeded, .failedSafeToRetry].contains(entry.events.last?.state)
        else {
          throw GraphValidationError.policyDenied
        }
        return
      }
      guard !hasTrustedHead(for: url) else { throw GraphValidationError.policyDenied }
      let identity = recordIdentity(for: key, digest: digest, recordURL: url)
      let event = Self.event(
        identity: identity, sequence: 1, state: .prepared, receiptDigest: nil, previousHash: nil)
      let created = Entry(
        schema: Self.schemaVersion, key: key, digest: digest, recordIdentity: identity,
        firstRetainedSequence: 1, previousRetainedHash: nil, events: [event])
      try checkpoint?(.beforeReplace)
      try SecureFile.writeNew(
        JSONEncoder().encode(
          created),
        to: url)
      try SecureFile.syncDirectory(containing: url)
      try checkpoint?(.afterReplace)
      try recordTrustedHead(
        for: url,
        entry: created)
    }
  }

  public func transition(
    _ key: MutationJournalKey, to state: MutationJournalState, receiptDigest: String? = nil
  ) throws {
    try withLock {
      try validatePhysicalNamespace()
      try validateNamespace(key)
      try ensureActive()
      let url = recordURL(for: key)
      let entry = try SecureFile.read(Entry.self, from: url)
      try validate(entry, recordURL: url)
      try validateTrustedHead(entry, recordURL: url)
      // Terminal recovery from outcomeUnknown is reserved for `reconcile`.
      // A general transition must never turn an ambiguous send into a claimed
      // result without fresh provider evidence.
      guard let current = entry.events.last, current.state != .outcomeUnknown, entry.key == key,
        Self.allowed(from: current.state).contains(state)
      else {
        throw GraphValidationError.policyDenied
      }
      let next = Self.event(
        identity: entry.recordIdentity,
        sequence: current.sequence + 1, state: state,
        receiptDigest: receiptDigest ?? current.receiptDigest, previousHash: current.hash)
      let updated = Entry(
        schema: entry.schema, key: key, digest: entry.digest, recordIdentity: entry.recordIdentity,
        firstRetainedSequence: entry.firstRetainedSequence,
        previousRetainedHash: entry.previousRetainedHash, events: entry.events + [next])
      try checkpoint?(.beforeReplace)
      try SecureFile.replace(JSONEncoder().encode(updated), at: url)
      try checkpoint?(.afterReplace)
      try recordTrustedHead(for: url, entry: updated)
    }
  }

  public func state(for key: MutationJournalKey) throws -> MutationJournalState? {
    return try withLock { () throws -> MutationJournalState? in
      try validatePhysicalNamespace()
      try validateNamespace(key)
      try ensureActive()
      let url = recordURL(for: key)
      guard FileManager.default.fileExists(atPath: url.path) else {
        guard !hasTrustedHead(for: url) else { throw GraphValidationError.policyDenied }
        return nil
      }
      let entry = try SecureFile.read(Entry.self, from: url)
      try validate(entry, recordURL: url)
      try validateTrustedHead(entry, recordURL: url)
      guard entry.key == key else { throw GraphValidationError.policyDenied }
      return entry.events.last?.state
    }
  }

  public func receiptStatus(for key: MutationJournalKey) throws -> Int? {
    return try withLock { () throws -> Int? in
      try validatePhysicalNamespace()
      try validateNamespace(key)
      try ensureActive()
      let url = recordURL(for: key)
      guard FileManager.default.fileExists(atPath: url.path) else {
        guard !hasTrustedHead(for: url) else { throw GraphValidationError.policyDenied }
        return nil
      }
      let entry = try SecureFile.read(Entry.self, from: url)
      try validate(entry, recordURL: url)
      try validateTrustedHead(entry, recordURL: url)
      guard entry.key == key, entry.events.last?.state == .succeeded,
        let receipt = entry.events.last?.receiptDigest,
        let status = Int(receipt.split(separator: "|", maxSplits: 1).first ?? "")
      else { return nil }
      return status
    }
  }

  /// Internal broker seam. It exposes only the opaque identity and current
  /// event hash needed by the independently protected head service.
  func brokerAnchor(for key: MutationJournalKey) throws -> BrokerJournalAnchor? {
    try withLock {
      try validatePhysicalNamespace()
      try validateNamespace(key)
      try ensureActive()
      let url = recordURL(for: key)
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      let entry = try SecureFile.read(Entry.self, from: url)
      try validate(entry, recordURL: url)
      guard entry.key == key, let event = entry.events.last else {
        throw GraphValidationError.policyDenied
      }
      return BrokerJournalAnchor(
        recordIdentity: entry.recordIdentity,
        head: try MetaTrustedHeadProtocol.TrustedHead(sequence: event.sequence, digest: event.hash))
    }
  }

  public func reconcile(
    _ key: MutationJournalKey, result: MutationReconciliationState
  ) throws -> MutationJournalState {
    return try withLock {
      try validatePhysicalNamespace()
      try validateNamespace(key)
      try ensureActive()
      let url = recordURL(for: key)
      let entry = try SecureFile.read(Entry.self, from: url)
      try validate(entry, recordURL: url)
      try validateTrustedHead(entry, recordURL: url)
      guard let current = entry.events.last, entry.key == key, current.state == .outcomeUnknown
      else { throw GraphValidationError.policyDenied }
      let target: MutationJournalState =
        switch result {
        case .verifiedEffect: .succeeded
        case .verifiedNoEffect: .failedSafeToRetry
        case .pending, .unavailable: .outcomeUnknown
        }
      guard target != .outcomeUnknown else { return current.state }
      let next = Self.event(
        identity: entry.recordIdentity,
        sequence: current.sequence + 1, state: target, receiptDigest: current.receiptDigest,
        previousHash: current.hash)
      let updated = Entry(
        schema: entry.schema, key: key, digest: entry.digest, recordIdentity: entry.recordIdentity,
        firstRetainedSequence: entry.firstRetainedSequence,
        previousRetainedHash: entry.previousRetainedHash, events: entry.events + [next])
      try checkpoint?(.beforeReplace)
      try SecureFile.replace(JSONEncoder().encode(updated), at: url)
      try checkpoint?(.afterReplace)
      try recordTrustedHead(for: url, entry: updated)
      return target
    }
  }

  /// Terminal entries retain their key/digest/state/receipt tombstone but may
  /// discard predecessor events. In-flight and retryable records are never
  /// compacted because their state transition history remains operational.
  public func compact(_ key: MutationJournalKey) throws {
    try withLock {
      try validatePhysicalNamespace()
      try validateNamespace(key)
      try ensureActive()
      let url = recordURL(for: key)
      let entry = try SecureFile.read(Entry.self, from: url)
      try validate(entry, recordURL: url)
      try validateTrustedHead(entry, recordURL: url)
      guard entry.key == key, let last = entry.events.last,
        [.succeeded, .outcomeUnknown].contains(last.state), entry.events.count > 1
      else { throw GraphValidationError.policyDenied }
      let compacted = Entry(
        schema: entry.schema, key: entry.key, digest: entry.digest,
        recordIdentity: entry.recordIdentity,
        firstRetainedSequence: last.sequence,
        previousRetainedHash: last.previousHash, events: [last])
      try checkpoint?(.beforeReplace)
      try SecureFile.replace(JSONEncoder().encode(compacted), at: url)
      try checkpoint?(.afterReplace)
      try recordTrustedHead(for: url, entry: compacted)
    }
  }

  /// Rotation intentionally creates a fresh namespace only after every record
  /// is terminal. Existing plans are bound to the old namespace and therefore
  /// cannot be replayed in the replacement directory.
  public func rotateNamespace(
    to newDirectory: URL, trustedHeadsDirectory: URL? = nil
  ) throws -> DurableMutationJournal {
    try withLock {
      try validatePhysicalNamespace()
      try ensureActive()
      let records = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
      ).filter { $0.pathExtension == "json" }
      for url in records {
        let entry = try SecureFile.read(Entry.self, from: url)
        try validate(entry, recordURL: url)
        try validateTrustedHead(entry, recordURL: url)
        guard let state = entry.events.last?.state, [.succeeded, .outcomeUnknown].contains(state)
        else { throw GraphValidationError.policyDenied }
      }
      try Self.createNamespace(at: newDirectory)
      if let trustedHeadsDirectory { try Self.createTrustedHeadStore(at: trustedHeadsDirectory) }
      let rotated = try DurableMutationJournal(
        directory: newDirectory, trustedHeadsDirectory: trustedHeadsDirectory)
      try SecureFile.writeNew(
        JSONEncoder().encode(RetiredNamespace(replacementNamespace: rotated.namespace)),
        to: directory.appendingPathComponent(".retired"))
      try SecureFile.syncDirectory(containing: directory)
      return rotated
    }
  }

  /// Internal administrative recovery for an interrupted anchor update. The
  /// privileged composition layer must supply independently verified
  /// expected-head evidence; ordinary mutation callers have no recovery path.
  func repairTrustedHeadAnchorAdministratively(
    for key: MutationJournalKey, expectedHead: TrustedHeadRecoveryExpectation
  ) throws {
    try withLock {
      try validatePhysicalNamespace()
      try validateNamespace(key)
      try ensureActive()
      let url = recordURL(for: key)
      let entry = try SecureFile.read(Entry.self, from: url)
      try validate(entry, recordURL: url)
      guard entry.key == key, let last = entry.events.last,
        let headURL = trustedHeadURL(for: url),
        FileManager.default.fileExists(atPath: headURL.path)
      else { throw GraphValidationError.policyDenied }
      let trusted = try SecureFile.read(TrustedHead.self, from: headURL)
      let advancesTrustedAnchor = last.sequence > trusted.sequence
      let compactsTrustedAnchor =
        last.sequence == trusted.sequence && last.hash == trusted.hash
        && entry.firstRetainedSequence > trusted.firstRetainedSequence
      guard trusted.schema == Self.schemaVersion, trusted.namespace == namespace,
        trusted.recordName == url.lastPathComponent,
        trusted.recordIdentity == entry.recordIdentity,
        Self.isDigest(trusted.hash),
        Self.isValidRetainedBoundary(
          trusted.firstRetainedSequence, trusted.previousRetainedHash,
          finalSequence: trusted.sequence),
        expectedHead.recordIdentity == entry.recordIdentity,
        expectedHead.firstRetainedSequence == entry.firstRetainedSequence,
        expectedHead.previousRetainedHash == entry.previousRetainedHash,
        expectedHead.anchoredFirstRetainedSequence == trusted.firstRetainedSequence,
        expectedHead.anchoredPreviousRetainedHash == trusted.previousRetainedHash,
        expectedHead.anchoredSequence == trusted.sequence,
        expectedHead.anchoredHash == trusted.hash,
        last.sequence == expectedHead.sequence,
        last.hash == expectedHead.hash,
        advancesTrustedAnchor || compactsTrustedAnchor
      else { throw GraphValidationError.policyDenied }
      try recordTrustedHead(for: url, entry: entry)
    }
  }

  private func recordURL(for key: MutationJournalKey) -> URL {
    directory.appendingPathComponent(
      MetaGraphWriter.digest(
        Self.canonicalMaterial(
          domain: "journal-record-name-v\(Self.schemaVersion)",
          fields: [key.namespace, key.principal, key.target, key.operationID, key.idempotencyKey]))
        + ".json")
  }

  private func recordIdentity(for key: MutationJournalKey, digest: String, recordURL: URL) -> String
  {
    MetaGraphWriter.digest(
      Self.canonicalMaterial(
        domain: "journal-record-identity-v\(Self.schemaVersion)",
        fields: [
          namespace, key.namespace, key.principal, key.target, key.operationID,
          key.idempotencyKey, digest, recordURL.lastPathComponent,
        ]))
  }

  private func validatePhysicalNamespace() throws {
    let marker = try SecureFile.read(
      NamespaceMarker.self, from: directory.appendingPathComponent(".namespace"))
    guard marker.schema == Self.schemaVersion, marker.value == namespace,
      !marker.value.isEmpty, marker.value.utf8.count <= 256
    else { throw GraphValidationError.policyDenied }
  }

  private func validateNamespace(_ key: MutationJournalKey) throws {
    guard key.namespace == namespace else { throw GraphValidationError.policyDenied }
  }

  private static func canonicalMaterial(domain: String, fields: [String]) -> Data {
    var material = Data()
    func append(_ value: Data) {
      var length = UInt64(value.count).bigEndian
      withUnsafeBytes(of: &length) { material.append(contentsOf: $0) }
      material.append(value)
    }
    append(Data(domain.utf8))
    for field in fields { append(Data(field.utf8)) }
    return material
  }

  private func ensureActive() throws {
    guard
      !FileManager.default.fileExists(
        atPath: directory.appendingPathComponent(".retired").path)
    else { throw GraphValidationError.policyDenied }
  }

  private func trustedHeadURL(for recordURL: URL) -> URL? {
    trustedHeadsDirectory.map {
      $0.appendingPathComponent(
        MetaGraphWriter.digest(Data(recordURL.lastPathComponent.utf8)) + ".json")
    }
  }

  private func hasTrustedHead(for recordURL: URL) -> Bool {
    guard let headURL = trustedHeadURL(for: recordURL) else { return false }
    return FileManager.default.fileExists(atPath: headURL.path)
  }

  private func recordTrustedHead(for recordURL: URL, entry: Entry) throws {
    guard let headURL = trustedHeadURL(for: recordURL), let last = entry.events.last else { return }
    let head = TrustedHead(
      schema: Self.schemaVersion, namespace: namespace, recordName: recordURL.lastPathComponent,
      recordIdentity: entry.recordIdentity, firstRetainedSequence: entry.firstRetainedSequence,
      previousRetainedHash: entry.previousRetainedHash, sequence: last.sequence, hash: last.hash)
    let bytes = try JSONEncoder().encode(head)
    if FileManager.default.fileExists(atPath: headURL.path) {
      try SecureFile.replace(bytes, at: headURL)
    } else {
      try SecureFile.writeNew(bytes, to: headURL)
      try SecureFile.syncDirectory(containing: headURL)
    }
  }

  private func validateTrustedHead(_ entry: Entry, recordURL: URL) throws {
    guard let headURL = trustedHeadURL(for: recordURL) else { return }
    guard FileManager.default.fileExists(atPath: headURL.path) else {
      throw GraphValidationError.policyDenied
    }
    let head = try SecureFile.read(TrustedHead.self, from: headURL)
    guard head.schema == Self.schemaVersion, head.namespace == namespace,
      head.recordName == recordURL.lastPathComponent, head.recordIdentity == entry.recordIdentity,
      Self.isDigest(head.recordIdentity), Self.isDigest(head.hash),
      Self.isValidRetainedBoundary(
        head.firstRetainedSequence, head.previousRetainedHash, finalSequence: head.sequence),
      head.firstRetainedSequence == entry.firstRetainedSequence,
      head.previousRetainedHash == entry.previousRetainedHash, let last = entry.events.last,
      last.sequence == head.sequence, last.hash == head.hash
    else { throw GraphValidationError.policyDenied }
  }

  private static func isDigest(_ value: String) -> Bool {
    value.wholeMatch(of: /[0-9a-f]{64}/) != nil
  }

  private static func isValidRetainedBoundary(
    _ firstRetainedSequence: UInt64, _ previousRetainedHash: String?, finalSequence: UInt64
  ) -> Bool {
    guard firstRetainedSequence > 0, firstRetainedSequence <= finalSequence else { return false }
    if firstRetainedSequence == 1 { return previousRetainedHash == nil }
    return previousRetainedHash.map(isDigest) ?? false
  }

  private func withLock<T>(_ body: () throws -> T) throws -> T {
    guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
      throw GraphValidationError.policyDenied
    }
    defer { _ = flock(lockDescriptor, LOCK_UN) }
    return try body()
  }

  private static func allowed(from state: MutationJournalState) -> Set<MutationJournalState> {
    switch state {
    case .prepared: [.inFlight]
    case .inFlight: [.succeeded, .failedSafeToRetry, .outcomeUnknown]
    case .failedSafeToRetry: [.inFlight]
    // These successors are valid only when appended by `reconcile` after its
    // result discriminator has bound fresh provider evidence. `transition`
    // separately rejects direct outcomeUnknown terminalization.
    case .outcomeUnknown: [.succeeded, .failedSafeToRetry]
    case .succeeded: []
    }
  }

  private static func event(
    identity: String, sequence: UInt64, state: MutationJournalState, receiptDigest: String?,
    previousHash: String?
  ) -> Event {
    let material =
      "\(schemaVersion)|\(identity)|\(sequence)|\(state.rawValue)|\(receiptDigest ?? "")|\(previousHash ?? "")"
    return Event(
      schema: schemaVersion, sequence: sequence, state: state, receiptDigest: receiptDigest,
      previousHash: previousHash,
      hash: MetaGraphWriter.digest(Data(material.utf8)))
  }

  private func validate(_ entry: Entry, recordURL: URL) throws {
    guard entry.schema == Self.schemaVersion, entry.key.namespace == namespace,
      recordURL.standardizedFileURL == self.recordURL(for: entry.key).standardizedFileURL,
      Self.isDigest(entry.digest), Self.isDigest(entry.recordIdentity),
      entry.recordIdentity
        == recordIdentity(for: entry.key, digest: entry.digest, recordURL: recordURL),
      let last = entry.events.last,
      Self.isValidRetainedBoundary(
        entry.firstRetainedSequence, entry.previousRetainedHash, finalSequence: last.sequence)
    else { throw GraphValidationError.policyDenied }
    var previousHash = entry.previousRetainedHash
    for (index, event) in entry.events.enumerated() {
      let expectedSequence = entry.firstRetainedSequence + UInt64(index)
      let expected = Self.event(
        identity: entry.recordIdentity, sequence: event.sequence, state: event.state,
        receiptDigest: event.receiptDigest,
        previousHash: event.previousHash)
      guard event.schema == Self.schemaVersion, event.sequence == expectedSequence,
        event.previousHash == previousHash,
        event.hash == expected.hash
      else { throw GraphValidationError.policyDenied }
      if index > 0 {
        guard Self.allowed(from: entry.events[index - 1].state).contains(event.state) else {
          throw GraphValidationError.policyDenied
        }
      }
      previousHash = event.hash
    }
  }

  private static func isSecureDirectory(_ directory: URL) -> Bool {
    var information = stat()
    return lstat(directory.path, &information) == 0 && (information.st_mode & S_IFMT) == S_IFDIR
      && information.st_uid == getuid() && (information.st_mode & (S_IRWXG | S_IRWXO)) == 0
  }
}
