import CryptoKit
import Foundation
import MetaGraphPrimitives

public enum MutationRisk: String, Codable, Sendable {
  case standard, highImpact, destructive, denied
}

public struct MutationPlan: Codable, Sendable, Equatable {
  public static let schemaVersion = 5
  public let schema: Int
  public let method: GraphMethod
  public let version: GraphAPIVersion
  public let path: GraphPath
  public let operationID: String
  public let queryDigest: String
  public let bodyDigest: String
  public let bodyMediaType: GraphBodyMediaType?
  public let requestDigest: String
  public let risk: MutationRisk
  public let policyDigest: String
  public let confirmation: MutationConfirmationClass
  public let mayAffectSpend: Bool
  /// Exact-request liability derived by `MutationPolicy`; it is never caller
  /// supplied authority and is covered by the canonical plan digest.
  public let requestedLiabilityCents: Int
  public let expiresAt: Int64
  /// Present only for a writer configured with a durable journal. Binding this
  /// value makes a preview unusable after journal namespace rotation.
  public let journalNamespace: String?
  public let digest: String

  fileprivate func canonicalBytes() -> Data {
    let namespace = journalNamespace ?? ""
    let mediaType = bodyMediaType?.rawValue ?? ""
    return Data(
      "\(schema)|\(method.rawValue)|\(version.description)|\(path.description)|\(operationID)|\(queryDigest)|\(bodyDigest)|\(mediaType)|\(requestDigest)|\(risk.rawValue)|\(policyDigest)|\(confirmation.rawValue)|\(mayAffectSpend)|\(requestedLiabilityCents)|\(expiresAt)|\(namespace)"
        .utf8)
  }
}

/// Credential-free analysis artifact emitted by the planning CLI. Its schema
/// intentionally differs from `MutationPlan`, so a plan file cannot be
/// decoded as an apply-capable plan if a future release enables a catalog row.
public struct OfflineMutationPlan: Codable, Sendable, Equatable {
  public static let schemaVersion = 1
  public let offlineSchema: Int
  public let operation: String
  public let method: String
  public let apiVersion: String
  public let relativePath: String
  public let planDigest: String
  public let transportEligibility: Bool

  fileprivate init(plan: MutationPlan) {
    offlineSchema = Self.schemaVersion
    operation = plan.operationID
    method = plan.method.rawValue
    apiVersion = plan.version.description
    relativePath = plan.path.description
    planDigest = plan.digest
    transportEligibility = false
  }
}

public struct ConfirmedMutationPlan: Sendable {
  fileprivate let plan: MutationPlan
  fileprivate init(_ plan: MutationPlan) { self.plan = plan }
}

public protocol MetaGraphWriting: Sendable {
  func plan(
    method: GraphMethod, version: GraphAPIVersion, path: GraphPath, query: GraphQuery, body: Data?,
    bodyMediaType: GraphBodyMediaType?, operationID: String?,
    now: Date
  ) throws -> MutationPlan
  func confirm(
    plan: MutationPlan, request: GraphRequest, confirmation: String,
    highImpactAcknowledgement: String?, now: Date
  ) throws -> ConfirmedMutationPlan
  func apply(
    _ plan: ConfirmedMutationPlan, query: GraphQuery, body: Data?,
    bodyMediaType: GraphBodyMediaType?
  ) async throws
    -> GraphResponse
}

public struct MetaGraphWriter: MetaGraphWriting {
  private let transport: any GraphTransport
  private let credentials: any GraphCredentialResolving
  private let applyDependencies: MutationApplyDependencies?
  private let currentDate: @Sendable () -> Date
  public init(
    transport: any GraphTransport,
    credentials: any GraphCredentialResolving = KinkoEnvironmentCredentials()
  ) {
    self.transport = transport
    self.credentials = credentials
    applyDependencies = nil
    currentDate = { Date() }
  }

  /// Internal-only construction for state-machine tests. Production callers
  /// cannot inject a local journal or verifier composition.
  init(
    transport: any GraphTransport, credentials: any GraphCredentialResolving,
    applyDependencies: MutationApplyDependencies,
    currentDate: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.transport = transport
    self.credentials = credentials
    self.applyDependencies = applyDependencies
    self.currentDate = currentDate
  }

  public func offlinePlan(
    method: GraphMethod, version: GraphAPIVersion, path: GraphPath,
    query: GraphQuery = try! GraphQuery(), body: Data? = nil,
    bodyMediaType: GraphBodyMediaType? = nil, operationID: String? = nil, now: Date = Date()
  ) throws -> OfflineMutationPlan {
    try OfflineMutationPlan(
      plan: plan(
        method: method, version: version, path: path, query: query, body: body,
        bodyMediaType: bodyMediaType, operationID: operationID, now: now))
  }
  public func plan(
    method: GraphMethod, version: GraphAPIVersion, path: GraphPath,
    query: GraphQuery = try! GraphQuery(), body: Data? = nil,
    bodyMediaType: GraphBodyMediaType? = nil, operationID: String? = nil, now: Date = Date()
  ) throws -> MutationPlan {
    guard method == .post else { throw GraphValidationError.policyDenied }
    let request = try GraphRequest(
      method: method, version: version, path: path, query: query, body: body,
      bodyMediaType: bodyMediaType, operationID: operationID)
    let policy = try MutationPolicy.classify(request)
    guard policy.risk != .denied else { throw GraphValidationError.policyDenied }
    let q = Self.digest(query.encoded().data(using: .utf8)!)
    let b = Self.digest(body ?? Data())
    let mediaType = bodyMediaType?.rawValue ?? ""
    let source = Self.digest(
      Data(
        "\(method.rawValue)|\(version)|\(path)|\(policy.operationID)|\(q)|\(b)|\(mediaType)".utf8))
    let plan = MutationPlan(
      schema: MutationPlan.schemaVersion, method: method, version: version, path: path,
      operationID: policy.operationID,
      queryDigest: q, bodyDigest: b, bodyMediaType: bodyMediaType, requestDigest: source,
      risk: policy.risk,
      policyDigest: policy.digest, confirmation: policy.confirmation,
      mayAffectSpend: policy.mayAffectSpend,
      requestedLiabilityCents: policy.requestedLiabilityCents,
      expiresAt: Int64(now.timeIntervalSince1970) + 900,
      journalNamespace: applyDependencies?.journal.namespace, digest: "")
    return MutationPlan(
      schema: plan.schema, method: plan.method, version: plan.version, path: plan.path,
      operationID: plan.operationID,
      queryDigest: plan.queryDigest, bodyDigest: plan.bodyDigest, bodyMediaType: plan.bodyMediaType,
      requestDigest: plan.requestDigest,
      risk: plan.risk, policyDigest: plan.policyDigest, confirmation: plan.confirmation,
      mayAffectSpend: plan.mayAffectSpend, requestedLiabilityCents: plan.requestedLiabilityCents,
      expiresAt: plan.expiresAt,
      journalNamespace: plan.journalNamespace,
      digest: Self.digest(plan.canonicalBytes()))
  }
  public func confirm(
    plan: MutationPlan, request: GraphRequest, confirmation: String,
    highImpactAcknowledgement: String? = nil, now: Date = Date()
  ) throws -> ConfirmedMutationPlan {
    guard plan.schema == MutationPlan.schemaVersion,
      Int64(now.timeIntervalSince1970) < plan.expiresAt
    else {
      throw GraphValidationError.planExpired
    }
    let policy = try MutationPolicy.classify(request)
    guard plan.digest == Self.digest(plan.canonicalBytes()),
      plan.method == request.method, plan.version == request.version, plan.path == request.path,
      plan.operationID == request.operationID, plan.operationID == policy.operationID,
      plan.bodyMediaType == request.bodyMediaType,
      plan.requestDigest
        == Self.requestDigest(
          method: request.method, version: request.version, path: request.path,
          query: request.query,
          body: request.body, bodyMediaType: request.bodyMediaType,
          operationID: request.operationID),
      plan.risk == policy.risk, plan.policyDigest == policy.digest,
      plan.confirmation == policy.confirmation, plan.mayAffectSpend == policy.mayAffectSpend,
      plan.requestedLiabilityCents == policy.requestedLiabilityCents,
      plan.digest == confirmation
    else {
      throw GraphValidationError.planMismatch
    }
    if plan.confirmation != .standard {
      guard highImpactAcknowledgement == plan.digest else {
        throw GraphValidationError.policyDenied
      }
    }
    return ConfirmedMutationPlan(plan)
  }
  public func apply(
    _ confirmed: ConfirmedMutationPlan, query: GraphQuery = try! GraphQuery(), body: Data? = nil,
    bodyMediaType: GraphBodyMediaType? = nil
  ) async throws -> GraphResponse {
    let plan = confirmed.plan
    // No mutable Meta operation has an enabled catalog row in this release.
    // Keep this public entry point permanently fail-closed until production
    // composition installs an exact, reviewed enabled operation.
    guard WriterCapabilityCatalog.allowsTransport(operationID: plan.operationID) else {
      throw GraphValidationError.policyDenied
    }
    guard plan.queryDigest == Self.digest(query.encoded().data(using: .utf8)!),
      plan.bodyDigest == Self.digest(body ?? Data())
    else { throw GraphValidationError.planMismatch }
    guard let dependencies = applyDependencies else { throw GraphValidationError.policyDenied }
    return try await applyForTesting(
      confirmed, query: query, body: body, bodyMediaType: bodyMediaType, dependencies: dependencies)
  }

  /// Executes only when a caller supplies provider-authenticated principal and
  /// asset verifiers, a durable namespace, and a descriptor-bound authorization.
  /// The default writer has no dependencies and therefore remains fail-closed.
  /// Internal test seam for the pre-existing journal state-machine tests. It
  /// is deliberately unavailable to clients of the Writer product and must
  /// never be used for production composition.
  func applyForTesting(
    _ confirmed: ConfirmedMutationPlan, query: GraphQuery = try! GraphQuery(), body: Data? = nil,
    bodyMediaType: GraphBodyMediaType? = nil,
    dependencies: MutationApplyDependencies
  ) async throws -> GraphResponse {
    let plan = confirmed.plan
    let request = try GraphRequest(
      method: plan.method, version: plan.version, path: plan.path, query: query, body: body,
      bodyMediaType: bodyMediaType, operationID: plan.operationID)
    let policy = try MutationPolicy.classify(request)
    guard isUnexpired(plan) else {
      throw GraphValidationError.planExpired
    }
    guard plan.queryDigest == Self.digest(query.encoded().data(using: .utf8)!),
      plan.bodyDigest == Self.digest(body ?? Data()), plan.bodyMediaType == bodyMediaType,
      plan.requestDigest
        == Self.requestDigest(
          method: request.method, version: request.version, path: request.path,
          query: request.query,
          body: request.body, bodyMediaType: request.bodyMediaType,
          operationID: request.operationID),
      plan.risk == policy.risk, plan.policyDigest == policy.digest,
      plan.confirmation == policy.confirmation, plan.mayAffectSpend == policy.mayAffectSpend,
      plan.requestedLiabilityCents == policy.requestedLiabilityCents,
      dependencies.authorization.descriptor.operationID == policy.operationID,
      dependencies.authorization.descriptor.method == plan.method,
      dependencies.authorization.descriptor.risk == policy.risk,
      dependencies.authorization.descriptor.confirmation == policy.confirmation,
      dependencies.authorization.descriptor.mayAffectSpend == policy.mayAffectSpend,
      dependencies.authorization.requestedLiabilityCents == policy.requestedLiabilityCents,
      plan.path.description == dependencies.authorization.descriptor.pathPrefix,
      plan.journalNamespace == dependencies.journal.namespace,
      dependencies.authorization.journalKey.namespace == dependencies.journal.namespace
    else { throw GraphValidationError.planMismatch }

    let authorization = dependencies.authorization
    try await dependencies.journal.prepare(authorization.journalKey, digest: plan.digest)
    if try await dependencies.journal.state(for: authorization.journalKey) == .succeeded {
      guard let status = try await dependencies.journal.receiptStatus(for: authorization.journalKey)
      else { throw GraphValidationError.policyDenied }
      return try GraphResponse(status: status, data: Data())
    }

    let credential = try credentials.resolve()
    let principal = try await dependencies.principalVerifier.verify(credential: credential)
    guard
      principal.matchesIdentity(authorization.expectedPrincipal),
      principal.isFresh(now: currentDate())
    else {
      throw GraphValidationError.policyDenied
    }
    let asset = try await dependencies.assetVerifier.verify(
      assetID: authorization.assetID, credential: credential)
    guard asset.assetID == authorization.assetID else { throw GraphValidationError.policyDenied }
    try SpendSafety.authorize(
      classification: asset.classification(now: currentDate()),
      requestedLiabilityCents: policy.requestedLiabilityCents,
      mayAffectSpend: policy.mayAffectSpend)

    guard isUnexpired(plan) else { throw GraphValidationError.planExpired }
    try await dependencies.journal.transition(authorization.journalKey, to: .inFlight)
    guard isUnexpired(plan) else {
      try await dependencies.journal.transition(authorization.journalKey, to: .failedSafeToRetry)
      throw GraphValidationError.planExpired
    }
    do {
      let response = try await transport.send(request, credential: credential)
      if (200...299).contains(response.status) {
        try await dependencies.journal.transition(
          authorization.journalKey, to: .succeeded,
          receiptDigest: "\(response.status)|\(Self.digest(response.data))")
        return response
      }
      if (400...499).contains(response.status), authorization.descriptor.permitsSafeRetry {
        try await dependencies.journal.transition(authorization.journalKey, to: .failedSafeToRetry)
        return response
      }
      try await dependencies.journal.transition(authorization.journalKey, to: .outcomeUnknown)
      throw GraphValidationError.invalidRequest
    } catch {
      if let state = try? await dependencies.journal.state(for: authorization.journalKey),
        state == .inFlight
      {
        try? await dependencies.journal.transition(authorization.journalKey, to: .outcomeUnknown)
      }
      throw error
    }
  }

  func applyForTesting(
    _ confirmed: ConfirmedMutationPlan, query: GraphQuery = try! GraphQuery(), body: Data? = nil,
    bodyMediaType: GraphBodyMediaType? = nil
  ) async throws -> GraphResponse {
    guard let dependencies = applyDependencies else { throw GraphValidationError.policyDenied }
    return try await applyForTesting(
      confirmed, query: query, body: body, bodyMediaType: bodyMediaType, dependencies: dependencies)
  }

  /// Kept internal for the migrated XCTest state-machine coverage. External
  /// Writer clients can only call the catalog-gated public overload above.
  func apply(
    _ confirmed: ConfirmedMutationPlan, query: GraphQuery = try! GraphQuery(), body: Data? = nil,
    bodyMediaType: GraphBodyMediaType? = nil,
    dependencies: MutationApplyDependencies
  ) async throws -> GraphResponse {
    try await applyForTesting(
      confirmed, query: query, body: body, bodyMediaType: bodyMediaType, dependencies: dependencies)
  }

  public func reconcile() async throws -> MutationReconciliationState {
    guard let dependencies = applyDependencies,
      WriterCapabilityCatalog.allowsTransport(
        operationID: dependencies.authorization.descriptor.operationID)
    else { throw GraphValidationError.policyDenied }
    return try await reconcileForTesting(dependencies: dependencies)
  }

  /// Internal state-machine seam. The public reconciliation path remains
  /// catalog-gated until a complete production composition is installed.
  func reconcileForTesting() async throws -> MutationReconciliationState {
    guard let dependencies = applyDependencies else { throw GraphValidationError.policyDenied }
    return try await reconcileForTesting(dependencies: dependencies)
  }

  private func reconcileForTesting(dependencies: MutationApplyDependencies) async throws
    -> MutationReconciliationState
  {
    guard let reconciler = dependencies.reconciler else {
      throw GraphValidationError.policyDenied
    }
    guard
      try await dependencies.journal.state(for: dependencies.authorization.journalKey)
        == .outcomeUnknown
    else { throw GraphValidationError.policyDenied }
    let credential = try credentials.resolve()
    let principal = try await dependencies.principalVerifier.verify(credential: credential)
    guard principal.matchesIdentity(dependencies.authorization.expectedPrincipal),
      principal.isFresh(now: currentDate())
    else {
      throw GraphValidationError.policyDenied
    }
    let asset = try await dependencies.assetVerifier.verify(
      assetID: dependencies.authorization.assetID, credential: credential)
    guard asset.assetID == dependencies.authorization.assetID else {
      throw GraphValidationError.policyDenied
    }
    try SpendSafety.authorize(
      classification: asset.classification(now: currentDate()),
      requestedLiabilityCents: dependencies.authorization.requestedLiabilityCents,
      mayAffectSpend: dependencies.authorization.descriptor.mayAffectSpend)
    let result = try await reconciler.reconcile(
      descriptor: dependencies.authorization.descriptor, path: confirmedPath(dependencies),
      credential: credential)
    _ = try await dependencies.journal.reconcile(
      dependencies.authorization.journalKey, result: result)
    return result
  }

  private func confirmedPath(_ dependencies: MutationApplyDependencies) throws -> GraphPath {
    try GraphPath(relative: dependencies.authorization.descriptor.pathPrefix)
  }
  private func isUnexpired(_ plan: MutationPlan) -> Bool {
    Int64(currentDate().timeIntervalSince1970) < plan.expiresAt
  }
  private static func requestDigest(
    method: GraphMethod, version: GraphAPIVersion, path: GraphPath, query: GraphQuery, body: Data?,
    bodyMediaType: GraphBodyMediaType?, operationID: String?
  ) -> String {
    let queryDigest = Self.digest(query.encoded().data(using: .utf8)!)
    let bodyDigest = Self.digest(body ?? Data())
    let mediaType = bodyMediaType?.rawValue ?? ""
    let operation = operationID ?? ""
    return Self.digest(
      Data(
        "\(method.rawValue)|\(version)|\(path)|\(operation)|\(queryDigest)|\(bodyDigest)|\(mediaType)"
          .utf8))
  }
  public static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
