import XCTest

@testable import MetaGraphPrimitives
@testable import MetaMarketingGatewayReaderKit
@testable import MetaMarketingGatewayWriterKit
@testable import MetaTrustedHeadProtocol

final class GraphSecurityTests: XCTestCase {
  private static let journalDigest = String(repeating: "a", count: 64)
  private static let differentJournalDigest = String(repeating: "b", count: 64)

  private func request(for plan: MutationPlan, body: Data? = Data("{}".utf8)) throws -> GraphRequest
  {
    try GraphRequest(
      method: plan.method, version: plan.version, path: plan.path, query: GraphQuery(), body: body,
      bodyMediaType: body == nil ? nil : .json, operationID: plan.operationID)
  }

  func testVersionAndPathRejectAmbiguousInputs() throws {
    XCTAssertEqual(try GraphAPIVersion("v26.0").description, "v26.0")
    for value in ["26.0", " v26.0", "v26.0/", "v0.0"] {
      XCTAssertThrowsError(try GraphAPIVersion(value))
    }
    for value in [
      "https://example.invalid/x", "//example.invalid/x", "me?access_token=x", "me/%2Fadmin",
      "me/../ads", "me\\ads",
    ] { XCTAssertThrowsError(try GraphPath(relative: value)) }
  }

  func testQueryRejectsCredentialSmugglingAndPreservesOrder() throws {
    XCTAssertEqual(
      try GraphQuery([("fields", "id"), ("fields", "name")]).encoded(), "fields=id&fields=name")
    for name in ["access_token", "ACCESS_TOKEN", "Authorization", "cookie"] {
      XCTAssertThrowsError(try GraphQuery([(name, "x")]))
    }
  }

  func testRequestUsesOnlyFixedMetaOrigin() throws {
    let request = try GraphRequest(
      method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "me/adaccounts"),
      query: GraphQuery([("fields", "id")]))
    XCTAssertEqual(
      try request.url().absoluteString, "https://graph.facebook.com/v26.0/me/adaccounts?fields=id")
  }

  func testPagingOnlyExtractsValidatedCursor() throws {
    XCTAssertEqual(
      try GraphPagination.cursor(
        from: "https://graph.facebook.com/v26.0/me?after=next", version: GraphAPIVersion("v26.0"))?
        .value, "next")
    XCTAssertThrowsError(
      try GraphPagination.cursor(
        from: "https://attacker.invalid/v26.0/me?after=next", version: GraphAPIVersion("v26.0")))
    XCTAssertThrowsError(
      try GraphPagination.cursor(
        from: "https://graph.facebook.com/v25.0/me?after=next", version: GraphAPIVersion("v26.0")))
  }

  func testWriterPlanBindsRequestAndHighRiskAcknowledgement() async throws {
    let writer = MetaGraphWriter(transport: NeverTransport(), credentials: TestCredentials())
    let plan = try writer.plan(
      method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_123/status"),
      body: Data("{}".utf8), bodyMediaType: .json, now: Date(timeIntervalSince1970: 100))
    XCTAssertEqual(plan.risk, .highImpact)
    XCTAssertThrowsError(
      try writer.confirm(
        plan: plan, request: try request(for: plan), confirmation: plan.digest,
        now: Date(timeIntervalSince1970: 101)))
    XCTAssertNoThrow(
      try writer.confirm(
        plan: plan, request: try request(for: plan), confirmation: plan.digest,
        highImpactAcknowledgement: plan.digest, now: Date(timeIntervalSince1970: 101)))
    let confirmed = try writer.confirm(
      plan: plan, request: try request(for: plan), confirmation: plan.digest,
      highImpactAcknowledgement: plan.digest, now: Date(timeIntervalSince1970: 101))
    await assertThrowsAsync(
      try await writer.apply(confirmed, body: Data("{}".utf8), bodyMediaType: .json))
  }

  func testOfflineArtifactHasDistinctNonExecutableSchema() throws {
    let writer = MetaGraphWriter(transport: NeverTransport(), credentials: TestCredentials())
    let offline = try writer.offlinePlan(
      method: .post, version: GraphAPIVersion("v26.0"),
      path: GraphPath(relative: "act_123/campaigns"), body: Data("{}".utf8), bodyMediaType: .json)
    let data = try JSONEncoder().encode(offline)

    XCTAssertFalse(offline.transportEligibility)
    XCTAssertThrowsError(try JSONDecoder().decode(MutationPlan.self, from: data))
  }

  func testPublicReconcileDeniesWithoutProductionComposition() async {
    let writer = MetaGraphWriter(transport: NeverTransport(), credentials: TestCredentials())
    await assertThrowsAsync(try await writer.reconcile())
  }

  func testBrokerBackedJournalAnchorsEveryTransitionAndRejectsLegacyHeads() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let legacyHeads = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.removeItem(at: legacyHeads)
    }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "broker-journal")
    try DurableMutationJournal.createTrustedHeadStore(at: legacyHeads)
    let legacy = try DurableMutationJournal(
      directory: directory, trustedHeadsDirectory: legacyHeads)
    let broker = InMemoryTrustedHeadClient()
    XCTAssertThrowsError(try BrokerBackedMutationJournal(journal: legacy, broker: broker))

    let journal = try DurableMutationJournal(directory: directory)
    let anchored = try BrokerBackedMutationJournal(journal: journal, broker: broker)
    let key = try MutationJournalKey(
      namespace: "broker-journal", principal: "app:actor", target: "act_1",
      operationID: "meta.generic.write", idempotencyKey: "broker-backed")
    try await anchored.prepare(key, digest: Self.journalDigest)
    let preparedSequence = await broker.sequence()
    XCTAssertEqual(preparedSequence, 1)
    try await anchored.transition(key, to: .inFlight)
    let inFlightSequence = await broker.sequence()
    let state = try await anchored.state(for: key)
    XCTAssertEqual(inFlightSequence, 2)
    XCTAssertEqual(state, .inFlight)
  }

  func testBrokerBackedJournalRetainsOutcomeUnknownWithoutCASForPendingOrUnavailable()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "broker-reconcile")
    let broker = InMemoryTrustedHeadClient()
    let journal = try DurableMutationJournal(directory: directory)
    let anchored = try BrokerBackedMutationJournal(journal: journal, broker: broker)
    let key = try MutationJournalKey(
      namespace: "broker-reconcile", principal: "app:actor", target: "act_1",
      operationID: "meta.generic.write", idempotencyKey: "pending-does-not-replay")

    try await anchored.prepare(key, digest: Self.journalDigest)
    try await anchored.transition(key, to: .inFlight)
    try await anchored.transition(key, to: .outcomeUnknown)
    let sequenceBefore = await broker.sequence()
    let casBefore = await broker.compareAndSetCalls()

    let pending = try await anchored.reconcile(key, result: .pending)
    let unavailable = try await anchored.reconcile(key, result: .unavailable)
    let sequenceAfterNoOp = await broker.sequence()
    let casAfterNoOp = await broker.compareAndSetCalls()
    XCTAssertEqual(pending, .outcomeUnknown)
    XCTAssertEqual(unavailable, .outcomeUnknown)
    XCTAssertEqual(sequenceAfterNoOp, sequenceBefore)
    XCTAssertEqual(casAfterNoOp, casBefore)

    let terminal = try await anchored.reconcile(key, result: .verifiedNoEffect)
    let sequenceAfterTerminal = await broker.sequence()
    let casAfterTerminal = await broker.compareAndSetCalls()
    XCTAssertEqual(terminal, .failedSafeToRetry)
    XCTAssertEqual(sequenceAfterTerminal, (sequenceBefore ?? 0) + 1)
    XCTAssertEqual(casAfterTerminal, casBefore + 1)
  }

  func testWriterTreatsBodyStatusAndBudgetAsHighImpact() throws {
    let writer = MetaGraphWriter(transport: NeverTransport(), credentials: TestCredentials())
    let version = try GraphAPIVersion("v26.0")
    let path = try GraphPath(relative: "act_1/name")
    let statusQuery = try GraphQuery([("status", "ACTIVE")])
    let budgetQuery = try GraphQuery([("daily_budget", "100")])

    let statusFromQuery = try writer.plan(
      method: .post, version: version, path: path, query: statusQuery, now: Date())
    let statusFromBody = try writer.plan(
      method: .post, version: version, path: path, body: Data(#"{"status":"ACTIVE"}"#.utf8),
      bodyMediaType: .json,
      now: Date())
    let budgetFromQuery = try writer.plan(
      method: .post, version: version, path: path, query: budgetQuery, now: Date())
    let budgetFromBody = try writer.plan(
      method: .post, version: version, path: path,
      body: Data(#"{"daily_budget":100}"#.utf8), bodyMediaType: .json, now: Date())
    let generic = try writer.plan(method: .post, version: version, path: path, now: Date())

    XCTAssertEqual(statusFromQuery.risk, .highImpact)
    XCTAssertEqual(statusFromBody.risk, .highImpact)
    XCTAssertEqual(statusFromQuery.confirmation, .spendAffecting)
    XCTAssertEqual(statusFromBody.confirmation, .spendAffecting)
    XCTAssertTrue(statusFromQuery.mayAffectSpend)
    XCTAssertTrue(statusFromBody.mayAffectSpend)
    XCTAssertEqual(budgetFromQuery.risk, .highImpact)
    XCTAssertEqual(budgetFromBody.risk, .highImpact)
    XCTAssertTrue(budgetFromQuery.mayAffectSpend)
    XCTAssertTrue(budgetFromBody.mayAffectSpend)
    XCTAssertEqual(budgetFromQuery.confirmation, .spendAffecting)
    XCTAssertEqual(budgetFromBody.confirmation, .spendAffecting)
    XCTAssertEqual(generic.risk, .highImpact)
    XCTAssertThrowsError(
      try writer.plan(
        method: .post, version: version, path: path, body: Data("not-json".utf8),
        bodyMediaType: .json, now: Date()))
  }

  func testMutationPolicyCoversClosedPathQueryAndBodyMatrix() throws {
    typealias Expected = (
      name: String, request: GraphRequest, risk: MutationRisk,
      confirmation: MutationConfirmationClass, mayAffectSpend: Bool, liability: Int
    )
    func request(
      method: GraphMethod = .post, path: String, query: [(String, String)] = [], body: String? = nil
    ) throws -> GraphRequest {
      try GraphRequest(
        method: method, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: path),
        query: GraphQuery(query), body: body.map { Data($0.utf8) },
        bodyMediaType: body == nil ? nil : .json)
    }
    let cases: [Expected] = [
      (
        "path-status", try request(path: "act_1/status"), .highImpact, .spendAffecting, true,
        0
      ),
      (
        "query-supported-alias",
        try request(
          path: "act_1/name", query: [("effective_status", "ACTIVE")]), .highImpact,
        .spendAffecting, true, 0
      ),
      (
        "nested-activation",
        try request(
          path: "act_1/name", body: #"{"changes":{"activate":true}}"#), .highImpact,
        .spendAffecting, true, 0
      ),
      (
        "list-budget",
        try request(
          path: "act_1/name", body: #"{"changes":[{"daily_budget":100}]}"#), .highImpact,
        .spendAffecting, true, 100
      ),
      (
        "targeting",
        try request(
          path: "act_1/name", body: #"{"targeting":{"geo_locations":["US"]}}"#), .highImpact,
        .highRisk, false, 0
      ),
      (
        "bid", try request(path: "act_1/name", body: #"{"bid_amount":15}"#), .highImpact,
        .spendAffecting, true, 15
      ),
      (
        "schedule",
        try request(
          path: "act_1/name", body: #"{"schedule":{"start_time":"2026-08-16"}}"#),
        .highImpact, .highRisk, false, 0
      ),
    ]
    for test in cases {
      let result = try MutationPolicy.classify(test.request)
      XCTAssertEqual(result.risk, test.risk, test.name)
      XCTAssertEqual(result.confirmation, test.confirmation, test.name)
      XCTAssertEqual(result.mayAffectSpend, test.mayAffectSpend, test.name)
      XCTAssertEqual(result.requestedLiabilityCents, test.liability, test.name)
      XCTAssertTrue(result.denialReasons.isEmpty, test.name)
    }

    let denied = try MutationPolicy.classify(
      request(path: "act_1/name", query: [("access", "grant")]))
    XCTAssertEqual(denied.risk, .denied)
    XCTAssertFalse(denied.denialReasons.isEmpty)
    XCTAssertEqual(
      try MutationPolicy.classify(
        request(path: "act_1/name", query: [("label", "safe")], body: nil)
      ).risk,
      .highImpact)
    XCTAssertThrowsError(
      try MutationPolicy.classify(
        request(path: "act_1/name", query: [("status", "ACTIVE"), ("STATUS", "PAUSED")]))
    )
    XCTAssertThrowsError(
      try MutationPolicy.classify(
        request(path: "act_1/name", body: #"{"status":"ACTIVE","status":"PAUSED"}"#))
    )
    let deepBody =
      String(repeating: #"{"nested":"#, count: 9) + "0" + String(repeating: "}", count: 9)
    XCTAssertThrowsError(try MutationPolicy.classify(request(path: "act_1/name", body: deepBody)))
    XCTAssertThrowsError(
      try GraphRequest(
        method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_1/name"),
        body: Data(repeating: 0x61, count: 1_048_577), bodyMediaType: .json)
    )
  }

  func testTypedOperationAllowlistRequiresBoundIdentityAndGenericEquivalentIsHighImpact()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let principal = try ProviderPrincipalEvidence(
      appID: "app", actorID: "actor", verifiedAt: Date())
    let descriptor = try MutationDescriptor(
      operationID: "meta.generic.write", method: .post, pathPrefix: "act_1/name",
      risk: .standard, confirmation: .standard)
    let key = try MutationJournalKey(
      namespace: "test", principal: principal.journalPrincipal, target: "act_1",
      operationID: descriptor.operationID, idempotencyKey: "operation-identity")
    let journal = try DurableMutationJournal(directory: directory)
    let dependencies = try MutationApplyDependencies(
      authorization: MutationApplyAuthorization(
        descriptor: descriptor, journalKey: key, expectedPrincipal: principal, assetID: "act_1",
        requestedLiabilityCents: 0),
      journal: journal, principalVerifier: StaticPrincipalVerifier(principal: principal),
      assetVerifier: FreshTestAssetVerifier(assetID: "act_1"), allowUnanchoredForTesting: true)
    let transport = RecordingMutationTransport(status: 200)
    let credentials = CountingCredentials()
    let writer = MetaGraphWriter(
      transport: transport, credentials: credentials, applyDependencies: dependencies)
    let version = try GraphAPIVersion("v26.0")
    let path = try GraphPath(relative: "act_1/name")
    let query = try GraphQuery([("name", "safe")])
    let typedPlan = try writer.plan(
      method: .post, version: version, path: path, query: query,
      operationID: "meta.ad-account.rename", now: Date())
    let genericPlan = try writer.plan(
      method: .post, version: version, path: path, query: query, now: Date())
    XCTAssertEqual(typedPlan.risk, .standard)
    XCTAssertEqual(typedPlan.confirmation, .standard)
    XCTAssertEqual(genericPlan.risk, .highImpact)
    let genericRequest = try GraphRequest(
      method: .post, version: version, path: path, query: query, operationID: "meta.generic.write")
    XCTAssertThrowsError(
      try writer.confirm(
        plan: typedPlan, request: genericRequest, confirmation: typedPlan.digest, now: Date()))
    let confirmed = try writer.confirm(
      plan: typedPlan,
      request: try GraphRequest(
        method: .post, version: version, path: path, query: query,
        operationID: "meta.ad-account.rename"),
      confirmation: typedPlan.digest, now: Date())
    await assertThrowsAsync(
      try await writer.apply(confirmed, query: query, dependencies: dependencies))
    let journalState = try await journal.state(for: key)
    let transportCalls = await transport.calls()
    XCTAssertNil(journalState)
    XCTAssertEqual(credentials.calls(), 0)
    XCTAssertEqual(transportCalls, 0)
  }

  func testWriterRejectsEachWeakerCallerAuthorizationClaimBeforeSideEffects() async throws {
    typealias Downgrade = (
      name: String, body: Data?, bodyMediaType: GraphBodyMediaType?,
      risk: MutationRisk, confirmation: MutationConfirmationClass, mayAffectSpend: Bool,
      requestedLiabilityCents: Int
    )
    let cases: [Downgrade] = [
      ("risk", nil, nil, .standard, .highRisk, false, 0),
      ("confirmation", nil, nil, .highImpact, .standard, false, 0),
      (
        "spend-effect", Data(#"{"daily_budget":100}"#.utf8), .json, .highImpact,
        .spendAffecting, false, 100
      ),
      (
        "liability", Data(#"{"daily_budget":100}"#.utf8), .json, .highImpact,
        .spendAffecting, true, 0
      ),
    ]
    let version = try GraphAPIVersion("v26.0")
    let path = try GraphPath(relative: "act_1/name")
    for test in cases {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
      let principal = try ProviderPrincipalEvidence(
        appID: "app", actorID: "actor", verifiedAt: Date())
      let descriptor = try MutationDescriptor(
        operationID: "meta.generic.write", method: .post, pathPrefix: path.description,
        risk: test.risk, confirmation: test.confirmation, mayAffectSpend: test.mayAffectSpend)
      let key = try MutationJournalKey(
        namespace: "test", principal: principal.journalPrincipal, target: "act_1",
        operationID: descriptor.operationID, idempotencyKey: "downgrade-\(test.name)")
      let journal = try DurableMutationJournal(directory: directory)
      let dependencies = try MutationApplyDependencies(
        authorization: MutationApplyAuthorization(
          descriptor: descriptor, journalKey: key, expectedPrincipal: principal, assetID: "act_1",
          requestedLiabilityCents: test.requestedLiabilityCents),
        journal: journal, principalVerifier: StaticPrincipalVerifier(principal: principal),
        assetVerifier: FreshTestAssetVerifier(assetID: "act_1"), allowUnanchoredForTesting: true)
      let credentials = CountingCredentials()
      let transport = RecordingMutationTransport(status: 200)
      let writer = MetaGraphWriter(
        transport: transport, credentials: credentials, applyDependencies: dependencies)
      let plan = try writer.plan(
        method: .post, version: version, path: path, body: test.body,
        bodyMediaType: test.bodyMediaType, now: Date())
      let request = try GraphRequest(
        method: .post, version: version, path: path, body: test.body,
        bodyMediaType: test.bodyMediaType)
      let confirmed = try writer.confirm(
        plan: plan, request: request, confirmation: plan.digest,
        highImpactAcknowledgement: plan.digest, now: Date())
      await assertThrowsAsync(
        try await writer.apply(
          confirmed, body: test.body, bodyMediaType: test.bodyMediaType,
          dependencies: dependencies))
      let journalState = try await journal.state(for: key)
      let transportCalls = await transport.calls()
      XCTAssertNil(journalState, test.name)
      XCTAssertEqual(credentials.calls(), 0, test.name)
      XCTAssertEqual(transportCalls, 0, test.name)
    }
  }

  func testWriterRejectsAmbiguousMutationInputBeforeJournalOrTransport() async throws {
    let writer = MetaGraphWriter(transport: NeverTransport(), credentials: TestCredentials())
    let version = try GraphAPIVersion("v26.0")
    let path = try GraphPath(relative: "act_1/status")
    XCTAssertThrowsError(
      try writer.plan(
        method: .post, version: version, path: path, body: Data("{}".utf8), now: Date()))
    XCTAssertThrowsError(
      try writer.plan(
        method: .post, version: version, path: path,
        query: GraphQuery([("status", "ACTIVE"), ("STATUS", "PAUSED")]), now: Date()))
    XCTAssertThrowsError(
      try writer.plan(
        method: .post, version: version, path: path,
        body: Data(#"{"status":"ACTIVE","status":"PAUSED"}"#.utf8), bodyMediaType: .json,
        now: Date()))
  }

  func testWriterDerivesBudgetLiabilityAndDeniesUnderstatedAuthorizationBeforeSideEffects()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let principal = try ProviderPrincipalEvidence(
      appID: "app", actorID: "actor", verifiedAt: Date())
    let descriptor = try MutationDescriptor(
      operationID: "meta.generic.write", method: .post, pathPrefix: "act_1/status",
      risk: .highImpact, confirmation: .spendAffecting, mayAffectSpend: true)
    let key = try MutationJournalKey(
      namespace: "test", principal: principal.journalPrincipal, target: "act_1",
      operationID: descriptor.operationID, idempotencyKey: "derived-liability")
    let journal = try DurableMutationJournal(directory: directory)
    let dependencies = try MutationApplyDependencies(
      authorization: MutationApplyAuthorization(
        descriptor: descriptor, journalKey: key, expectedPrincipal: principal, assetID: "act_1",
        requestedLiabilityCents: 0), journal: journal,
      principalVerifier: StaticPrincipalVerifier(principal: principal),
      assetVerifier: FreshTestAssetVerifier(assetID: "act_1"), allowUnanchoredForTesting: true)
    let transport = RecordingMutationTransport(status: 200)
    let credentials = CountingCredentials()
    let writer = MetaGraphWriter(
      transport: transport, credentials: credentials, applyDependencies: dependencies)
    let body = Data(#"{"daily_budget":100}"#.utf8)
    let plan = try writer.plan(
      method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_1/status"),
      body: body, bodyMediaType: .json, now: Date())
    XCTAssertEqual(plan.requestedLiabilityCents, 100)
    XCTAssertEqual(
      try MutationPolicy.classify(try request(for: plan, body: body)).requestedLiabilityCents, 100)
    let confirmed = try writer.confirm(
      plan: plan, request: try request(for: plan, body: body), confirmation: plan.digest,
      highImpactAcknowledgement: plan.digest, now: Date())
    await assertThrowsAsync(
      try await writer.apply(
        confirmed, body: body, bodyMediaType: .json, dependencies: dependencies))
    let journalState = try await journal.state(for: key)
    let transportCalls = await transport.calls()
    XCTAssertNil(journalState)
    XCTAssertEqual(credentials.calls(), 0)
    XCTAssertEqual(transportCalls, 0)
  }

  func testWriterTransportUsesPolicyAuthorizedContentType() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UploadURLProtocol.self]
    let transport = URLSessionGraphTransport(configuration: configuration)
    UploadURLProtocol.recorder.configure(response: Data("{}".utf8))
    let request = try GraphRequest(
      method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_1/name"),
      body: Data(#"{"name":"safe"}"#.utf8), bodyMediaType: .json)

    _ = try await transport.sendForTesting(request, credential: GraphCredential(token: "sentinel"))
    XCTAssertEqual(UploadURLProtocol.recorder.snapshot().contentType, "application/json")
    UploadURLProtocol.recorder.configure(response: Data("{}".utf8))
    let bodyFree = try GraphRequest(
      method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_1/name"))
    _ = try await transport.sendForTesting(bodyFree, credential: GraphCredential(token: "sentinel"))
    let bodyFreeSnapshot = UploadURLProtocol.recorder.snapshot()
    XCTAssertEqual(bodyFreeSnapshot.requestCount, 1)
    XCTAssertEqual(bodyFreeSnapshot.body, Data())
    XCTAssertNil(bodyFreeSnapshot.contentType)
    XCTAssertThrowsError(
      try GraphRequest(
        method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_1/name"),
        body: Data("{}".utf8)))
  }

  func testWriterRejectsPostPlanBodyQueryAndMediaTamperingBeforeSideEffects() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let principal = try ProviderPrincipalEvidence(
      appID: "app", actorID: "actor", verifiedAt: Date())
    let descriptor = try MutationDescriptor(
      operationID: "meta.generic.write", method: .post, pathPrefix: "act_1/name",
      risk: .highImpact, confirmation: .highRisk)
    let key = try MutationJournalKey(
      namespace: "test", principal: principal.journalPrincipal, target: "act_1",
      operationID: descriptor.operationID, idempotencyKey: "post-plan-tamper")
    let journal = try DurableMutationJournal(directory: directory)
    let dependencies = try MutationApplyDependencies(
      authorization: MutationApplyAuthorization(
        descriptor: descriptor, journalKey: key, expectedPrincipal: principal, assetID: "act_1",
        requestedLiabilityCents: 0),
      journal: journal, principalVerifier: StaticPrincipalVerifier(principal: principal),
      assetVerifier: FreshTestAssetVerifier(assetID: "act_1"), allowUnanchoredForTesting: true)
    let credentials = CountingCredentials()
    let transport = RecordingMutationTransport(status: 200)
    let writer = MetaGraphWriter(
      transport: transport, credentials: credentials, applyDependencies: dependencies)
    let body = Data(#"{"name":"safe"}"#.utf8)
    let plan = try writer.plan(
      method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_1/name"),
      body: body, bodyMediaType: .json, now: Date())
    let confirmed = try writer.confirm(
      plan: plan, request: try request(for: plan, body: body), confirmation: plan.digest,
      highImpactAcknowledgement: plan.digest, now: Date())
    await assertThrowsAsync(
      try await writer.apply(confirmed, body: body, bodyMediaType: nil, dependencies: dependencies))
    await assertThrowsAsync(
      try await writer.apply(
        confirmed, query: GraphQuery([("status", "ACTIVE")]), body: body, bodyMediaType: .json,
        dependencies: dependencies))
    await assertThrowsAsync(
      try await writer.apply(
        confirmed, body: Data(#"{"name":"changed"}"#.utf8), bodyMediaType: .json,
        dependencies: dependencies))
    let journalState = try await journal.state(for: key)
    let transportCalls = await transport.calls()
    XCTAssertNil(journalState)
    XCTAssertEqual(credentials.calls(), 0)
    XCTAssertEqual(transportCalls, 0)
  }

  func testWriterRejectsTamperedPlanFieldsEvenWhenDigestIsReused() throws {
    let writer = MetaGraphWriter(transport: NeverTransport(), credentials: TestCredentials())
    let plan = try writer.plan(
      method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_123/name"),
      now: Date(timeIntervalSince1970: 100))
    let tampered = MutationPlan(
      schema: plan.schema, method: plan.method, version: plan.version,
      path: try GraphPath(relative: "act_999/name"), operationID: plan.operationID,
      queryDigest: plan.queryDigest,
      bodyDigest: plan.bodyDigest, bodyMediaType: plan.bodyMediaType,
      requestDigest: plan.requestDigest, risk: plan.risk,
      policyDigest: plan.policyDigest, confirmation: plan.confirmation,
      mayAffectSpend: plan.mayAffectSpend, requestedLiabilityCents: plan.requestedLiabilityCents,
      expiresAt: plan.expiresAt, journalNamespace: plan.journalNamespace, digest: plan.digest)
    XCTAssertThrowsError(
      try writer.confirm(
        plan: tampered, request: try request(for: plan), confirmation: plan.digest,
        now: Date(timeIntervalSince1970: 101)))
  }

  func testWriterApplyUsesBoundEvidenceAndReturnsDurableReceiptWithoutResend() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let principal = try ProviderPrincipalEvidence(
      appID: "app", actorID: "actor", verifiedAt: Date())
    let descriptor = try MutationDescriptor(
      operationID: "meta.generic.write", method: .post, pathPrefix: "act_1/status",
      risk: .highImpact, confirmation: .spendAffecting, mayAffectSpend: true)
    let key = try MutationJournalKey(
      namespace: "test", principal: principal.journalPrincipal, target: "act_1",
      operationID: descriptor.operationID, idempotencyKey: "one")
    let dependencies = try MutationApplyDependencies(
      authorization: MutationApplyAuthorization(
        descriptor: descriptor, journalKey: key, expectedPrincipal: principal, assetID: "act_1",
        requestedLiabilityCents: 0), journal: DurableMutationJournal(directory: directory),
      principalVerifier: StaticPrincipalVerifier(principal: principal),
      assetVerifier: FreshTestAssetVerifier(assetID: "act_1"), allowUnanchoredForTesting: true)
    let transport = RecordingMutationTransport(status: 200)
    let writer = MetaGraphWriter(
      transport: transport, credentials: TestCredentials(), applyDependencies: dependencies)
    let plan = try writer.plan(
      method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_1/status"),
      body: Data("{}".utf8), bodyMediaType: .json, now: Date())
    let confirmed = try writer.confirm(
      plan: plan, request: try request(for: plan), confirmation: plan.digest,
      highImpactAcknowledgement: plan.digest, now: Date())
    let first = try await writer.applyForTesting(
      confirmed, body: Data("{}".utf8), bodyMediaType: .json)
    let replay = try await writer.applyForTesting(
      confirmed, body: Data("{}".utf8), bodyMediaType: .json)
    let calls = await transport.calls()
    XCTAssertEqual(first.status, 200)
    XCTAssertEqual(replay.status, 200)
    XCTAssertEqual(calls, 1)
  }

  func testWriterReconciliationNeverReplaysUnknownOutcome() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let principal = try ProviderPrincipalEvidence(
      appID: "app", actorID: "actor", verifiedAt: Date())
    let descriptor = try MutationDescriptor(
      operationID: "meta.generic.write", method: .post, pathPrefix: "act_1/status",
      risk: .highImpact, confirmation: .spendAffecting, mayAffectSpend: true)
    let key = try MutationJournalKey(
      namespace: "test", principal: principal.journalPrincipal, target: "act_1",
      operationID: descriptor.operationID, idempotencyKey: "unknown")
    let dependencies = try MutationApplyDependencies(
      authorization: MutationApplyAuthorization(
        descriptor: descriptor, journalKey: key, expectedPrincipal: principal, assetID: "act_1",
        requestedLiabilityCents: 0), journal: DurableMutationJournal(directory: directory),
      principalVerifier: StaticPrincipalVerifier(principal: principal),
      assetVerifier: FreshTestAssetVerifier(assetID: "act_1"),
      reconciler: StaticReconciler(result: .pending), allowUnanchoredForTesting: true)
    let transport = RecordingMutationTransport(status: 500)
    let writer = MetaGraphWriter(
      transport: transport, credentials: TestCredentials(), applyDependencies: dependencies)
    let plan = try writer.plan(
      method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_1/status"),
      body: Data("{}".utf8), bodyMediaType: .json, now: Date())
    let confirmed = try writer.confirm(
      plan: plan, request: try request(for: plan), confirmation: plan.digest,
      highImpactAcknowledgement: plan.digest, now: Date())
    await assertThrowsAsync(
      try await writer.applyForTesting(confirmed, body: Data("{}".utf8), bodyMediaType: .json))
    let reconciliation = try await writer.reconcileForTesting()
    await assertThrowsAsync(
      try await writer.applyForTesting(confirmed, body: Data("{}".utf8), bodyMediaType: .json))
    let calls = await transport.calls()
    XCTAssertEqual(reconciliation, .pending)
    XCTAssertEqual(calls, 1)
  }

  func testWriterRejectsAuthorizationAssetPathMismatch() throws {
    let principal = try ProviderPrincipalEvidence(
      appID: "app", actorID: "actor", verifiedAt: Date())
    let descriptor = try MutationDescriptor(
      operationID: "meta.generic.write", method: .post, pathPrefix: "act_1/status",
      risk: .highImpact, confirmation: .spendAffecting, mayAffectSpend: true)
    let mismatchedKey = try MutationJournalKey(
      namespace: "test", principal: principal.journalPrincipal, target: "act_2",
      operationID: descriptor.operationID, idempotencyKey: "mismatch")
    XCTAssertThrowsError(
      try MutationApplyAuthorization(
        descriptor: descriptor, journalKey: mismatchedKey, expectedPrincipal: principal,
        assetID: "act_2", requestedLiabilityCents: 0))
  }

  func testReconcileRejectsMismatchedAssetEvidence() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let principal = try ProviderPrincipalEvidence(
      appID: "app", actorID: "actor", verifiedAt: Date())
    let descriptor = try MutationDescriptor(
      operationID: "meta.generic.write", method: .post, pathPrefix: "act_1/status",
      risk: .highImpact, confirmation: .spendAffecting, mayAffectSpend: true)
    let key = try MutationJournalKey(
      namespace: "test", principal: principal.journalPrincipal, target: "act_1",
      operationID: descriptor.operationID, idempotencyKey: "reconcile-mismatch")
    let journal = try DurableMutationJournal(directory: directory)
    try await journal.prepare(key, digest: Self.journalDigest)
    try await journal.transition(key, to: .inFlight)
    try await journal.transition(key, to: .outcomeUnknown)
    let reconciler = CountingReconciler()
    let dependencies = try MutationApplyDependencies(
      authorization: MutationApplyAuthorization(
        descriptor: descriptor, journalKey: key, expectedPrincipal: principal, assetID: "act_1",
        requestedLiabilityCents: 0), journal: journal,
      principalVerifier: StaticPrincipalVerifier(principal: principal),
      assetVerifier: StaticAssetVerifier(
        evidence: try VerifiedTestAssetEvidence(
          assetID: "act_2", providerVerifiedAt: Date(), nonBillable: true)),
      reconciler: reconciler, allowUnanchoredForTesting: true)
    let writer = MetaGraphWriter(
      transport: NeverTransport(), credentials: TestCredentials(), applyDependencies: dependencies)
    await assertThrowsAsync(try await writer.reconcile())
    let calls = await reconciler.calls()
    XCTAssertEqual(calls, 0)
  }

  func testWriterRechecksExpiryBeforeCreatingJournalRecord() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let expected = try ProviderPrincipalEvidence(appID: "app", actorID: "actor", verifiedAt: Date())
    let descriptor = try MutationDescriptor(
      operationID: "meta.generic.write", method: .post, pathPrefix: "act_1/status",
      risk: .highImpact, confirmation: .spendAffecting, mayAffectSpend: true)
    let key = try MutationJournalKey(
      namespace: "test", principal: expected.journalPrincipal, target: "act_1",
      operationID: descriptor.operationID, idempotencyKey: "expired")
    let journal = try DurableMutationJournal(directory: directory)
    let dependencies = try MutationApplyDependencies(
      authorization: MutationApplyAuthorization(
        descriptor: descriptor, journalKey: key, expectedPrincipal: expected, assetID: "act_1",
        requestedLiabilityCents: 0), journal: journal,
      principalVerifier: StaticPrincipalVerifier(principal: expected),
      assetVerifier: StaticAssetVerifier(
        evidence: try VerifiedTestAssetEvidence(
          assetID: "act_1", providerVerifiedAt: Date(), nonBillable: true)
      ), allowUnanchoredForTesting: true)
    let transport = RecordingMutationTransport(status: 200)
    let writer = MetaGraphWriter(
      transport: transport, credentials: TestCredentials(), applyDependencies: dependencies)
    let plan = try writer.plan(
      method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_1/status"),
      body: Data("{}".utf8), bodyMediaType: .json, now: Date(timeIntervalSinceNow: -1_000))
    let confirmed = try writer.confirm(
      plan: plan, request: try request(for: plan), confirmation: plan.digest,
      highImpactAcknowledgement: plan.digest, now: Date(timeIntervalSinceNow: -999))
    await assertThrowsAsync(
      try await writer.apply(
        confirmed, body: Data("{}".utf8), bodyMediaType: .json, dependencies: dependencies))
    let journalState = try await journal.state(for: key)
    let calls = await transport.calls()
    XCTAssertNil(journalState)
    XCTAssertEqual(calls, 0)
  }

  func testWriterAcceptsFreshEvidenceAfterSameIdentityCredentialRotation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let expected = try ProviderPrincipalEvidence(
      appID: "app", actorID: "actor", verifiedAt: Date(timeIntervalSinceNow: -1))
    let refreshed = try ProviderPrincipalEvidence(
      appID: "app", actorID: "actor", verifiedAt: Date())
    let descriptor = try MutationDescriptor(
      operationID: "meta.generic.write", method: .post, pathPrefix: "act_1/status",
      risk: .highImpact, confirmation: .spendAffecting, mayAffectSpend: true)
    let key = try MutationJournalKey(
      namespace: "test", principal: expected.journalPrincipal, target: "act_1",
      operationID: descriptor.operationID, idempotencyKey: "rotated")
    let dependencies = try MutationApplyDependencies(
      authorization: MutationApplyAuthorization(
        descriptor: descriptor, journalKey: key, expectedPrincipal: expected, assetID: "act_1",
        requestedLiabilityCents: 0), journal: DurableMutationJournal(directory: directory),
      principalVerifier: StaticPrincipalVerifier(principal: refreshed),
      assetVerifier: StaticAssetVerifier(
        evidence: try VerifiedTestAssetEvidence(
          assetID: "act_1", providerVerifiedAt: Date(), nonBillable: true)
      ), allowUnanchoredForTesting: true)
    let transport = RecordingMutationTransport(status: 200)
    let writer = MetaGraphWriter(
      transport: transport, credentials: TestCredentials(), applyDependencies: dependencies)
    let plan = try writer.plan(
      method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_1/status"),
      body: Data("{}".utf8), bodyMediaType: .json, now: Date())
    let confirmed = try writer.confirm(
      plan: plan, request: try request(for: plan), confirmation: plan.digest,
      highImpactAcknowledgement: plan.digest, now: Date())
    let response = try await writer.apply(
      confirmed, body: Data("{}".utf8), bodyMediaType: .json, dependencies: dependencies)
    let calls = await transport.calls()
    XCTAssertEqual(response.status, 200)
    XCTAssertEqual(calls, 1)
  }

  func testWriterRecoversPreparedRecordAfterPreSendCredentialFailure() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let principal = try ProviderPrincipalEvidence(
      appID: "app", actorID: "actor", verifiedAt: Date())
    let descriptor = try MutationDescriptor(
      operationID: "meta.generic.write", method: .post, pathPrefix: "act_1/status",
      risk: .highImpact, confirmation: .spendAffecting, mayAffectSpend: true)
    let key = try MutationJournalKey(
      namespace: "test", principal: principal.journalPrincipal, target: "act_1",
      operationID: descriptor.operationID, idempotencyKey: "pre-send")
    let journal = try DurableMutationJournal(directory: directory)
    let dependencies = try MutationApplyDependencies(
      authorization: MutationApplyAuthorization(
        descriptor: descriptor, journalKey: key, expectedPrincipal: principal, assetID: "act_1",
        requestedLiabilityCents: 0), journal: journal,
      principalVerifier: StaticPrincipalVerifier(principal: principal),
      assetVerifier: FreshTestAssetVerifier(assetID: "act_1"), allowUnanchoredForTesting: true)
    let transport = RecordingMutationTransport(status: 200)
    let writer = MetaGraphWriter(
      transport: transport, credentials: FailingOnceCredentials(), applyDependencies: dependencies)
    let plan = try writer.plan(
      method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_1/status"),
      body: Data("{}".utf8), bodyMediaType: .json, now: Date())
    let confirmed = try writer.confirm(
      plan: plan, request: try request(for: plan), confirmation: plan.digest,
      highImpactAcknowledgement: plan.digest, now: Date())
    await assertThrowsAsync(
      try await writer.applyForTesting(confirmed, body: Data("{}".utf8), bodyMediaType: .json))
    let prepared = try await journal.state(for: key)
    let response = try await writer.applyForTesting(
      confirmed, body: Data("{}".utf8), bodyMediaType: .json)
    let calls = await transport.calls()
    XCTAssertEqual(prepared, .prepared)
    XCTAssertEqual(response.status, 200)
    XCTAssertEqual(calls, 1)
  }

  func testWriterRechecksExpiryAtTheSendBoundary() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let origin = Date(timeIntervalSince1970: 1_000)
    let principal = try ProviderPrincipalEvidence(
      appID: "app", actorID: "actor", verifiedAt: origin)
    let descriptor = try MutationDescriptor(
      operationID: "meta.generic.write", method: .post, pathPrefix: "act_1/status",
      risk: .highImpact, confirmation: .spendAffecting, mayAffectSpend: true)
    let key = try MutationJournalKey(
      namespace: "test", principal: principal.journalPrincipal, target: "act_1",
      operationID: descriptor.operationID, idempotencyKey: "late-expiry")
    let journal = try DurableMutationJournal(directory: directory)
    let dependencies = try MutationApplyDependencies(
      authorization: MutationApplyAuthorization(
        descriptor: descriptor, journalKey: key, expectedPrincipal: principal, assetID: "act_1",
        requestedLiabilityCents: 0), journal: journal,
      principalVerifier: StaticPrincipalVerifier(principal: principal),
      assetVerifier: StaticAssetVerifier(
        evidence: try VerifiedTestAssetEvidence(
          assetID: "act_1", providerVerifiedAt: origin, nonBillable: true)),
      allowUnanchoredForTesting: true)
    let transport = RecordingMutationTransport(status: 200)
    let clock = SteppingDateClock(
      values: [origin, origin, origin, origin, origin.addingTimeInterval(901)])
    let writer = MetaGraphWriter(
      transport: transport, credentials: TestCredentials(), applyDependencies: dependencies,
      currentDate: { clock.now() })
    let plan = try writer.plan(
      method: .post, version: GraphAPIVersion("v26.0"), path: GraphPath(relative: "act_1/status"),
      body: Data("{}".utf8), bodyMediaType: .json, now: origin)
    let confirmed = try writer.confirm(
      plan: plan, request: try request(for: plan), confirmation: plan.digest,
      highImpactAcknowledgement: plan.digest, now: origin)
    await assertThrowsAsync(
      try await writer.apply(
        confirmed, body: Data("{}".utf8), bodyMediaType: .json, dependencies: dependencies))
    let journalState = try await journal.state(for: key)
    let calls = await transport.calls()
    XCTAssertEqual(journalState, .failedSafeToRetry)
    XCTAssertEqual(calls, 0)
  }

  func testSpendSafetyRequiresFreshProviderVerifiedNonBillableAssetAndUSDZero() throws {
    let evidence = try VerifiedTestAssetEvidence(
      assetID: "test_1", providerVerifiedAt: Date(timeIntervalSince1970: 100), nonBillable: true)
    XCTAssertEqual(
      evidence.classification(now: Date(timeIntervalSince1970: 200)), .verifiedNonBillableTest)
    XCTAssertEqual(evidence.classification(now: Date(timeIntervalSince1970: 401)), .live)
    XCTAssertNoThrow(
      try SpendSafety.authorize(
        classification: .verifiedNonBillableTest, requestedLiabilityCents: 0, mayAffectSpend: false)
    )
    XCTAssertThrowsError(
      try SpendSafety.authorize(
        classification: .verifiedNonBillableTest, requestedLiabilityCents: 1, mayAffectSpend: true))
    XCTAssertThrowsError(
      try SpendSafety.authorize(
        classification: .live, requestedLiabilityCents: 0, mayAffectSpend: false))
  }

  func testMutationJournalTombstonesUnknownOutcomes() async throws {
    let journal = MutationJournal()
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "key-1")
    try await journal.prepare(key, digest: Self.journalDigest)
    try await journal.transition(key, to: .inFlight)
    try await journal.transition(key, to: .outcomeUnknown)
    await assertThrowsAsync(try await journal.prepare(key, digest: Self.journalDigest))
  }

  func testDurableJournalPersistsUnknownOutcomeTombstone() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "key-1")
    XCTAssertThrowsError(try DurableMutationJournal(directory: directory))
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let journal = try DurableMutationJournal(directory: directory)
    try await journal.prepare(key, digest: Self.journalDigest)
    try await journal.transition(key, to: .inFlight)
    try await journal.transition(key, to: .outcomeUnknown)
    let reloaded = try DurableMutationJournal(directory: directory)
    let state = try await reloaded.state(for: key)
    XCTAssertEqual(state, .outcomeUnknown)
    await assertThrowsAsync(try await reloaded.prepare(key, digest: Self.journalDigest))
  }

  func testDurableJournalRejectsTamperedEventChain() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "chain")
    let journal = try DurableMutationJournal(directory: directory)
    try await journal.prepare(key, digest: Self.journalDigest)
    try await journal.transition(key, to: .inFlight)
    let record = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
      ).first { $0.pathExtension == "json" })
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
    var events = try XCTUnwrap(object["events"] as? [[String: Any]])
    events[1]["hash"] = "0"
    object["events"] = events
    try JSONSerialization.data(withJSONObject: object).write(to: record)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
    let reloaded = try DurableMutationJournal(directory: directory)
    await assertThrowsAsync(try await reloaded.state(for: key))
  }

  func testTrustedHeadRejectsDigestTampering() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("journal")
    let heads = root.appendingPathComponent("heads")
    defer { try? FileManager.default.removeItem(at: root) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    try DurableMutationJournal.createTrustedHeadStore(at: heads)
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "digest-tamper")
    let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    try await journal.prepare(key, digest: String(repeating: "a", count: 64))
    let record = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
    object["digest"] = String(repeating: "b", count: 64)
    try JSONSerialization.data(withJSONObject: object).write(to: record)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
    let reloaded = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    await assertThrowsAsync(try await reloaded.state(for: key))
  }

  func testTrustedHeadRejectsIndependentFieldTamperingAcrossOperations() async throws {
    let fields = [
      "schema", "namespace", "recordName", "recordIdentity", "firstRetainedSequence",
      "previousRetainedHash", "sequence", "hash",
    ]
    func fixture(
      root: URL, idempotencyKey: String, transitions: Int
    ) async throws -> (journal: DurableMutationJournal, key: MutationJournalKey, heads: URL) {
      let directory = root.appendingPathComponent("journal")
      let heads = root.appendingPathComponent("heads")
      try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
      try DurableMutationJournal.createTrustedHeadStore(at: heads)
      let key = try MutationJournalKey(
        namespace: "test", principal: "app:actor", target: "act_1",
        operationID: "meta.generic.write",
        idempotencyKey: idempotencyKey)
      let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
      try await journal.prepare(key, digest: Self.journalDigest)
      if transitions >= 1 { try await journal.transition(key, to: .inFlight) }
      if transitions >= 2 {
        try await journal.transition(key, to: .succeeded, receiptDigest: "200|receipt")
      }
      return (journal, key, heads)
    }
    func headURL(in heads: URL) throws -> URL {
      try XCTUnwrap(
        try FileManager.default.contentsOfDirectory(at: heads, includingPropertiesForKeys: nil)
          .first { $0.pathExtension == "json" })
    }
    func tamper(_ head: URL, field: String) throws {
      var object = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: Data(contentsOf: head)) as? [String: Any])
      switch field {
      case "schema": object[field] = 1
      case "namespace": object[field] = "other"
      case "recordName": object[field] = "other.json"
      case "recordIdentity", "previousRetainedHash", "hash":
        object[field] = String(repeating: "b", count: 64)
      case "firstRetainedSequence": object[field] = 2
      case "sequence": object[field] = 2
      default: XCTFail("unknown trusted-head field \(field)")
      }
      try JSONSerialization.data(withJSONObject: object).write(to: head)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: head.path)
    }

    let repairControlRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: repairControlRoot) }
    let repairControl = try await fixture(
      root: repairControlRoot, idempotencyKey: "head-repair-control", transitions: 0)
    let repairControlHead = try headURL(in: repairControl.heads)
    let repairControlAnchor = try Data(contentsOf: repairControlHead)
    try await repairControl.journal.transition(repairControl.key, to: .inFlight)
    try repairControlAnchor.write(to: repairControlHead)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: repairControlHead.path)
    try await repairControl.journal.repairTrustedHeadAnchorAdministratively(
      for: repairControl.key,
      expectedHead: try trustedHeadExpectation(
        from: repairControlRoot.appendingPathComponent("journal"),
        trustedHeadData: repairControlAnchor))
    let repairedState = try await repairControl.journal.state(for: repairControl.key)
    XCTAssertEqual(repairedState, .inFlight)

    for field in fields {
      let transitionRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: transitionRoot) }
      let transitionFixture = try await fixture(
        root: transitionRoot, idempotencyKey: "head-transition-\(field)", transitions: 0)
      try tamper(try headURL(in: transitionFixture.heads), field: field)
      await assertThrowsAsync(try await transitionFixture.journal.state(for: transitionFixture.key))
      await assertThrowsAsync(
        try await transitionFixture.journal.transition(transitionFixture.key, to: .inFlight))

      let terminalRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: terminalRoot) }
      let terminalFixture = try await fixture(
        root: terminalRoot, idempotencyKey: "head-terminal-\(field)", transitions: 2)
      try tamper(try headURL(in: terminalFixture.heads), field: field)
      await assertThrowsAsync(try await terminalFixture.journal.state(for: terminalFixture.key))
      await assertThrowsAsync(try await terminalFixture.journal.compact(terminalFixture.key))
      await assertThrowsAsync(
        try await terminalFixture.journal.rotateNamespace(
          to: terminalRoot.appendingPathComponent("rotated"),
          trustedHeadsDirectory: terminalRoot.appendingPathComponent("rotated-heads")))

      let repairRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: repairRoot) }
      let repairFixture = try await fixture(
        root: repairRoot, idempotencyKey: "head-repair-\(field)", transitions: 0)
      let repairHead = try headURL(in: repairFixture.heads)
      let staleAnchor = try Data(contentsOf: repairHead)
      try await repairFixture.journal.transition(repairFixture.key, to: .inFlight)
      try staleAnchor.write(to: repairHead)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: repairHead.path)
      try tamper(repairHead, field: field)
      let expected = try trustedHeadExpectation(
        from: repairRoot.appendingPathComponent("journal"), trustedHeadData: staleAnchor)
      await assertThrowsAsync(
        try await repairFixture.journal.repairTrustedHeadAnchorAdministratively(
          for: repairFixture.key, expectedHead: expected))
    }
  }

  func testTrustedHeadRepairRejectsIdentityMismatchedAnchor() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("journal")
    let heads = root.appendingPathComponent("heads")
    defer { try? FileManager.default.removeItem(at: root) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    try DurableMutationJournal.createTrustedHeadStore(at: heads)
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "identity-repair")
    let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    try await journal.prepare(key, digest: String(repeating: "a", count: 64))
    let head = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: heads, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    let staleAnchor = try Data(contentsOf: head)
    try await journal.transition(key, to: .inFlight)
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: staleAnchor) as? [String: Any])
    object["recordIdentity"] = String(repeating: "0", count: 64)
    try JSONSerialization.data(withJSONObject: object).write(to: head)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: head.path)
    await assertThrowsAsync(
      try await journal.repairTrustedHeadAnchorAdministratively(
        for: key,
        expectedHead: try trustedHeadExpectation(from: directory, trustedHeadData: staleAnchor)))
  }

  func testTrustedHeadRepairRejectsTamperedRetainedBoundary() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("journal")
    let heads = root.appendingPathComponent("heads")
    defer { try? FileManager.default.removeItem(at: root) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    try DurableMutationJournal.createTrustedHeadStore(at: heads)
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "boundary-repair")
    let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    try await journal.prepare(key, digest: Self.journalDigest)
    let head = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: heads, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    let originalHead = try Data(contentsOf: head)
    try await journal.transition(key, to: .inFlight)
    var tamperedHead = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: originalHead) as? [String: Any])
    tamperedHead["firstRetainedSequence"] = 2
    tamperedHead["previousRetainedHash"] = String(repeating: "0", count: 64)
    try JSONSerialization.data(withJSONObject: tamperedHead).write(to: head)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: head.path)
    await assertThrowsAsync(
      try await journal.repairTrustedHeadAnchorAdministratively(
        for: key,
        expectedHead: try trustedHeadExpectation(from: directory, trustedHeadData: originalHead)))
  }

  func testTrustedHeadRepairRecoversInterruptedCompactionAnchorUpdate() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("journal")
    let heads = root.appendingPathComponent("heads")
    defer { try? FileManager.default.removeItem(at: root) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    try DurableMutationJournal.createTrustedHeadStore(at: heads)
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "interrupted-compaction")
    let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    try await journal.prepare(key, digest: Self.journalDigest)
    try await journal.transition(key, to: .inFlight)
    try await journal.transition(key, to: .succeeded, receiptDigest: "200|receipt")
    let head = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: heads, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    let priorAnchor = try Data(contentsOf: head)
    let interrupted = try DurableMutationJournal(
      directory: directory, trustedHeadsDirectory: heads,
      checkpoint: { checkpoint in
        guard checkpoint != .afterReplace else { throw GraphValidationError.policyDenied }
      })
    await assertThrowsAsync(try await interrupted.compact(key))
    let recovery = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    let expected = try trustedHeadExpectation(from: directory, trustedHeadData: priorAnchor)
    try await recovery.repairTrustedHeadAnchorAdministratively(for: key, expectedHead: expected)
    let state = try await recovery.state(for: key)
    let receiptStatus = try await recovery.receiptStatus(for: key)
    XCTAssertEqual(state, .succeeded)
    XCTAssertEqual(receiptStatus, 200)
  }

  func testTrustedHeadRepairRejectsBackwardCompactionBoundary() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("journal")
    let heads = root.appendingPathComponent("heads")
    defer { try? FileManager.default.removeItem(at: root) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    try DurableMutationJournal.createTrustedHeadStore(at: heads)
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "backward-compaction")
    let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    try await journal.prepare(key, digest: Self.journalDigest)
    try await journal.transition(key, to: .inFlight)
    try await journal.transition(key, to: .succeeded, receiptDigest: "200|receipt")
    let record = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    let preCompactionRecord = try Data(contentsOf: record)
    let head = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: heads, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    try await journal.compact(key)
    let compactedAnchor = try Data(contentsOf: head)
    try preCompactionRecord.write(to: record)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
    let recovery = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    await assertThrowsAsync(
      try await recovery.repairTrustedHeadAnchorAdministratively(
        for: key,
        expectedHead: try trustedHeadExpectation(from: directory, trustedHeadData: compactedAnchor))
    )
  }

  func testDurableJournalRejectsMalformedPlanDigestBeforeCreatingRecord() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "malformed-digest")
    let journal = try DurableMutationJournal(directory: directory)
    await assertThrowsAsync(try await journal.prepare(key, digest: "digest"))
    let records = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }
    XCTAssertTrue(records.isEmpty)
  }

  func testDurableJournalRejectsLegacyRecordSchemaWithoutAutomaticMigration() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "legacy-record")
    let journal = try DurableMutationJournal(directory: directory)
    try await journal.prepare(key, digest: String(repeating: "a", count: 64))
    let record = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
    object["schema"] = 1
    let legacyBytes = try JSONSerialization.data(withJSONObject: object)
    try legacyBytes.write(to: record)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
    let reloaded = try DurableMutationJournal(directory: directory)
    await assertThrowsAsync(try await reloaded.state(for: key))
    XCTAssertEqual(try Data(contentsOf: record), legacyBytes)
    let marker = directory.appendingPathComponent(".namespace")
    var markerObject = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: marker)) as? [String: Any])
    markerObject["value"] = "other"
    try JSONSerialization.data(withJSONObject: markerObject).write(to: marker)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
    let namespaceReloaded = try DurableMutationJournal(directory: directory)
    await assertThrowsAsync(try await namespaceReloaded.state(for: key))
    markerObject.removeValue(forKey: "schema")
    try JSONSerialization.data(withJSONObject: markerObject).write(to: marker)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
    XCTAssertThrowsError(try DurableMutationJournal(directory: directory))
  }

  func testTrustedHeadRejectsLegacySchemaBeforeUse() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("journal")
    let heads = root.appendingPathComponent("heads")
    defer { try? FileManager.default.removeItem(at: root) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    try DurableMutationJournal.createTrustedHeadStore(at: heads)
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "legacy-head")
    let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    try await journal.prepare(key, digest: String(repeating: "a", count: 64))
    let head = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: heads, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: head)) as? [String: Any])
    object["schema"] = 1
    try JSONSerialization.data(withJSONObject: object).write(to: head)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: head.path)
    let reloaded = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    await assertThrowsAsync(try await reloaded.state(for: key))
  }

  func testDurableJournalRejectsLegacyEventSchemaBeforeUse() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "legacy-event")
    let journal = try DurableMutationJournal(directory: directory)
    try await journal.prepare(key, digest: String(repeating: "a", count: 64))
    let record = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
    var events = try XCTUnwrap(object["events"] as? [[String: Any]])
    events[0]["schema"] = 1
    object["events"] = events
    try JSONSerialization.data(withJSONObject: object).write(to: record)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
    let reloaded = try DurableMutationJournal(directory: directory)
    await assertThrowsAsync(try await reloaded.state(for: key))
  }

  func testDurableJournalRejectsKeyNamespaceAndRetainedBoundaryTampering() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("journal")
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "key-tamper")
    let journal = try DurableMutationJournal(directory: directory)
    try await journal.prepare(key, digest: String(repeating: "a", count: 64))
    let record = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    var keyTampered = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
    var encodedKey = try XCTUnwrap(keyTampered["key"] as? [String: Any])
    encodedKey["principal"] = "app:other"
    keyTampered["key"] = encodedKey
    try JSONSerialization.data(withJSONObject: keyTampered).write(to: record)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
    let keyReloaded = try DurableMutationJournal(directory: directory)
    await assertThrowsAsync(try await keyReloaded.state(for: key))

    let namespaceDirectory = root.appendingPathComponent("namespace")
    try DurableMutationJournal.createNamespace(at: namespaceDirectory, namespace: "test")
    let namespaceJournal = try DurableMutationJournal(directory: namespaceDirectory)
    try await namespaceJournal.prepare(key, digest: String(repeating: "a", count: 64))
    let marker = namespaceDirectory.appendingPathComponent(".namespace")
    var namespaceMarker = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: marker)) as? [String: Any])
    namespaceMarker["value"] = "other"
    try JSONSerialization.data(withJSONObject: namespaceMarker).write(to: marker)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
    let namespaceReloaded = try DurableMutationJournal(directory: namespaceDirectory)
    await assertThrowsAsync(try await namespaceReloaded.state(for: key))

    let boundaryDirectory = root.appendingPathComponent("boundary")
    try DurableMutationJournal.createNamespace(at: boundaryDirectory, namespace: "test")
    let boundaryJournal = try DurableMutationJournal(directory: boundaryDirectory)
    try await boundaryJournal.prepare(key, digest: String(repeating: "a", count: 64))
    try await boundaryJournal.transition(key, to: .inFlight)
    try await boundaryJournal.transition(key, to: .succeeded, receiptDigest: "200|receipt")
    try await boundaryJournal.compact(key)
    let boundaryRecord = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(
        at: boundaryDirectory, includingPropertiesForKeys: nil
      )
      .first { $0.pathExtension == "json" })
    var boundaryTampered = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: boundaryRecord)) as? [String: Any])
    boundaryTampered["firstRetainedSequence"] = 1
    try JSONSerialization.data(withJSONObject: boundaryTampered).write(to: boundaryRecord)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: boundaryRecord.path)
    let boundaryReloaded = try DurableMutationJournal(directory: boundaryDirectory)
    await assertThrowsAsync(try await boundaryReloaded.state(for: key))
  }

  func testDurableJournalRejectsEveryKeyFieldAndRecordIdentityTampering() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "complete-key")
    let replacements = [
      ("namespace", "other"), ("principal", "app:other"), ("target", "act_2"),
      ("operationID", "meta.other.write"), ("idempotencyKey", "different-key"),
    ]
    for (field, replacement) in replacements {
      let directory = root.appendingPathComponent(field)
      try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
      let journal = try DurableMutationJournal(directory: directory)
      try await journal.prepare(key, digest: String(repeating: "a", count: 64))
      let record = try XCTUnwrap(
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
          .first { $0.pathExtension == "json" })
      var object = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
      var encodedKey = try XCTUnwrap(object["key"] as? [String: Any])
      encodedKey[field] = replacement
      object["key"] = encodedKey
      try JSONSerialization.data(withJSONObject: object).write(to: record)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
      let reloaded = try DurableMutationJournal(directory: directory)
      await assertThrowsAsync(try await reloaded.state(for: key))
    }

    let identityDirectory = root.appendingPathComponent("identity")
    try DurableMutationJournal.createNamespace(at: identityDirectory, namespace: "test")
    let identityJournal = try DurableMutationJournal(directory: identityDirectory)
    try await identityJournal.prepare(key, digest: String(repeating: "a", count: 64))
    let record = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(
        at: identityDirectory, includingPropertiesForKeys: nil
      )
      .first { $0.pathExtension == "json" })
    var identityTampered = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
    identityTampered["recordIdentity"] = String(repeating: "0", count: 64)
    try JSONSerialization.data(withJSONObject: identityTampered).write(to: record)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
    let identityReloaded = try DurableMutationJournal(directory: identityDirectory)
    await assertThrowsAsync(try await identityReloaded.state(for: key))
  }

  func testDurableJournalRejectsDelimiterRebindingAcrossCanonicalKeyMaterial() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("journal")
    let heads = root.appendingPathComponent("heads")
    defer { try? FileManager.default.removeItem(at: root) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    try DurableMutationJournal.createTrustedHeadStore(at: heads)
    let first = try MutationJournalKey(
      namespace: "test", principal: "app|actor", target: "act_1",
      operationID: "meta.generic.write", idempotencyKey: "complete-key")
    let second = try MutationJournalKey(
      namespace: "test", principal: "app", target: "actor|act_1",
      operationID: "meta.generic.write", idempotencyKey: "complete-key")
    let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    try await journal.prepare(first, digest: Self.journalDigest)
    let record = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    var entry = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
    var encodedKey = try XCTUnwrap(entry["key"] as? [String: Any])
    encodedKey["principal"] = second.principal
    encodedKey["target"] = second.target
    entry["key"] = encodedKey
    try JSONSerialization.data(withJSONObject: entry).write(to: record)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)

    let reloaded = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    let initialSecondState = try await reloaded.state(for: second)
    XCTAssertNil(initialSecondState)
    try await reloaded.prepare(second, digest: Self.journalDigest)
    let preparedSecondState = try await reloaded.state(for: second)
    XCTAssertEqual(preparedSecondState, .prepared)
    let records = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }
    XCTAssertEqual(records.count, 2)
  }

  func testDurableJournalRejectsPostOpenNamespaceMarkerTamperingAcrossOperations() async throws {
    enum Operation: CaseIterable {
      case prepare, state, receiptStatus, transition, reconcile, compact, rotate, repair
    }
    func markerURL(in directory: URL) -> URL { directory.appendingPathComponent(".namespace") }
    func tamperMarker(in directory: URL) throws {
      let marker = markerURL(in: directory)
      var object = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: Data(contentsOf: marker)) as? [String: Any])
      object["value"] = "tampered"
      try JSONSerialization.data(withJSONObject: object).write(to: marker)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
    }

    for operation in Operation.allCases {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      let directory = root.appendingPathComponent("journal")
      let heads = root.appendingPathComponent("heads")
      defer { try? FileManager.default.removeItem(at: root) }
      try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
      try DurableMutationJournal.createTrustedHeadStore(at: heads)
      let key = try MutationJournalKey(
        namespace: "test", principal: "app:actor", target: "act_1",
        operationID: "meta.generic.write", idempotencyKey: "marker-\(operation)")
      let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
      try await journal.prepare(key, digest: Self.journalDigest)

      switch operation {
      case .repair:
        let head = try XCTUnwrap(
          try FileManager.default.contentsOfDirectory(at: heads, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "json" })
        let staleAnchor = try Data(contentsOf: head)
        try await journal.transition(key, to: .inFlight)
        try staleAnchor.write(to: head)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: head.path)
        let expected = try trustedHeadExpectation(from: directory, trustedHeadData: staleAnchor)
        try tamperMarker(in: directory)
        await assertThrowsAsync(
          try await journal.repairTrustedHeadAnchorAdministratively(
            for: key, expectedHead: expected))
      case .prepare:
        try tamperMarker(in: directory)
        await assertThrowsAsync(try await journal.prepare(key, digest: Self.journalDigest))
      case .state:
        try tamperMarker(in: directory)
        await assertThrowsAsync(try await journal.state(for: key))
      case .receiptStatus:
        try tamperMarker(in: directory)
        await assertThrowsAsync(try await journal.receiptStatus(for: key))
      case .transition:
        try tamperMarker(in: directory)
        await assertThrowsAsync(try await journal.transition(key, to: .inFlight))
      case .reconcile:
        try tamperMarker(in: directory)
        await assertThrowsAsync(try await journal.reconcile(key, result: .verifiedEffect))
      case .compact:
        try tamperMarker(in: directory)
        await assertThrowsAsync(try await journal.compact(key))
      case .rotate:
        try tamperMarker(in: directory)
        await assertThrowsAsync(
          try await journal.rotateNamespace(
            to: root.appendingPathComponent("rotated"),
            trustedHeadsDirectory: root.appendingPathComponent("rotated-heads")))
      }
    }
  }

  func testDurableJournalRejectsCanonicalFilenameRebindingWhenTrustedHeadExists() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("journal")
    let heads = root.appendingPathComponent("heads")
    defer { try? FileManager.default.removeItem(at: root) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    try DurableMutationJournal.createTrustedHeadStore(at: heads)
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "filename-rebind")
    let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    try await journal.prepare(key, digest: String(repeating: "a", count: 64))
    let record = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    try FileManager.default.moveItem(
      at: record, to: directory.appendingPathComponent("rebound.json"))
    let reloaded = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    await assertThrowsAsync(try await reloaded.state(for: key))
    await assertThrowsAsync(
      try await reloaded.prepare(key, digest: String(repeating: "a", count: 64)))
  }

  func testDurableJournalCompactionRetainsTerminalTombstone() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "compact")
    let journal = try DurableMutationJournal(directory: directory)
    try await journal.prepare(key, digest: Self.journalDigest)
    try await journal.transition(key, to: .inFlight)
    try await journal.transition(key, to: .succeeded, receiptDigest: "200|receipt")
    try await journal.compact(key)
    let state = try await journal.state(for: key)
    let receiptStatus = try await journal.receiptStatus(for: key)
    XCTAssertEqual(state, .succeeded)
    XCTAssertEqual(receiptStatus, 200)
    await assertThrowsAsync(try await journal.prepare(key, digest: Self.differentJournalDigest))
  }

  func testDurableJournalTrustedHeadRejectsRollbackAndAllowsRotationOnlyWhenTerminal() async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("journal")
    let heads = root.appendingPathComponent("heads")
    defer { try? FileManager.default.removeItem(at: root) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    try DurableMutationJournal.createTrustedHeadStore(at: heads)
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "head")
    let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    try await journal.prepare(key, digest: Self.journalDigest)
    try await journal.transition(key, to: .inFlight)
    await assertThrowsAsync(
      try await journal.rotateNamespace(to: root.appendingPathComponent("rotated")))
    let record = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    let oldBytes = try Data(contentsOf: record)
    try await journal.transition(key, to: .succeeded, receiptDigest: "200|receipt")
    let rotated = try await journal.rotateNamespace(to: root.appendingPathComponent("rotated"))
    await assertThrowsAsync(try await rotated.state(for: key))
    let rotatedKey = try MutationJournalKey(
      namespace: rotated.namespace, principal: "app:actor", target: "act_1",
      operationID: "meta.generic.write", idempotencyKey: "head")
    let rotatedState = try await rotated.state(for: rotatedKey)
    XCTAssertNil(rotatedState)
    await assertThrowsAsync(try await rotated.prepare(key, digest: Self.journalDigest))
    try oldBytes.write(to: record)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
    XCTAssertThrowsError(
      try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads))
  }

  func testDurableJournalRejectsMissingConfiguredTrustedHead() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("journal")
    let heads = root.appendingPathComponent("heads")
    defer { try? FileManager.default.removeItem(at: root) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    try DurableMutationJournal.createTrustedHeadStore(at: heads)
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "missing-anchor")
    let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    try await journal.prepare(key, digest: Self.journalDigest)
    let head = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: heads, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    try FileManager.default.removeItem(at: head)
    let reloaded = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    await assertThrowsAsync(try await reloaded.state(for: key))
  }

  func testDurableJournalRejectsStaleTrustedHeadUntilExplicitRepair() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("journal")
    let heads = root.appendingPathComponent("heads")
    defer { try? FileManager.default.removeItem(at: root) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    try DurableMutationJournal.createTrustedHeadStore(at: heads)
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "stale-anchor")
    let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    try await journal.prepare(key, digest: Self.journalDigest)
    let anchor = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: heads, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    let staleAnchor = try Data(contentsOf: anchor)
    try await journal.transition(key, to: .inFlight)
    try staleAnchor.write(to: anchor)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: anchor.path)
    await assertThrowsAsync(try await journal.state(for: key))
    let expectation = try trustedHeadExpectation(
      from: directory, trustedHeadData: staleAnchor)
    let mismatchedExpectation = try TrustedHeadRecoveryExpectation(
      recordIdentity: expectation.recordIdentity,
      firstRetainedSequence: expectation.firstRetainedSequence,
      previousRetainedHash: expectation.previousRetainedHash,
      sequence: expectation.sequence, hash: String(repeating: "0", count: 64),
      anchoredFirstRetainedSequence: expectation.anchoredFirstRetainedSequence,
      anchoredPreviousRetainedHash: expectation.anchoredPreviousRetainedHash,
      anchoredSequence: expectation.anchoredSequence, anchoredHash: expectation.anchoredHash)
    await assertThrowsAsync(
      try await journal.repairTrustedHeadAnchorAdministratively(
        for: key, expectedHead: mismatchedExpectation))
    try await journal.repairTrustedHeadAnchorAdministratively(for: key, expectedHead: expectation)
    let repairedState = try await journal.state(for: key)
    XCTAssertEqual(repairedState, .inFlight)
  }

  func testTrustedHeadRepairCannotReplaceNewerAnchorWithRolledBackRecord() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("journal")
    let heads = root.appendingPathComponent("heads")
    defer { try? FileManager.default.removeItem(at: root) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    try DurableMutationJournal.createTrustedHeadStore(at: heads)
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "repair-rollback")
    let journal = try DurableMutationJournal(directory: directory, trustedHeadsDirectory: heads)
    try await journal.prepare(key, digest: Self.journalDigest)
    let record = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    let rolledBackRecord = try Data(contentsOf: record)
    try await journal.transition(key, to: .inFlight)
    try rolledBackRecord.write(to: record)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
    let anchor = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: heads, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "json" })
    let rolledBackExpectation = try trustedHeadExpectation(
      from: directory, trustedHeadData: Data(contentsOf: anchor))
    await assertThrowsAsync(
      try await journal.repairTrustedHeadAnchorAdministratively(
        for: key, expectedHead: rolledBackExpectation))
  }

  func testDurableJournalRetiredActorRejectsEveryOperation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let directory = root.appendingPathComponent("journal")
    defer { try? FileManager.default.removeItem(at: root) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "retired-actor")
    let journal = try DurableMutationJournal(directory: directory)
    try await journal.prepare(key, digest: Self.journalDigest)
    try await journal.transition(key, to: .inFlight)
    try await journal.transition(key, to: .succeeded, receiptDigest: "200|receipt")
    _ = try await journal.rotateNamespace(to: root.appendingPathComponent("rotated"))
    await assertThrowsAsync(try await journal.prepare(key, digest: Self.journalDigest))
    await assertThrowsAsync(try await journal.transition(key, to: .inFlight))
    await assertThrowsAsync(try await journal.state(for: key))
    await assertThrowsAsync(try await journal.receiptStatus(for: key))
    await assertThrowsAsync(try await journal.reconcile(key, result: .verifiedEffect))
    await assertThrowsAsync(try await journal.compact(key))
    await assertThrowsAsync(
      try await journal.rotateNamespace(to: root.appendingPathComponent("again")))
  }

  func testProductionApplyDependenciesRequireTrustedHeadAnchor() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let principal = try ProviderPrincipalEvidence(
      appID: "app", actorID: "actor", verifiedAt: Date())
    let descriptor = try MutationDescriptor(
      operationID: "meta.generic.write", method: .post, pathPrefix: "act_1/status",
      risk: .highImpact, confirmation: .spendAffecting, mayAffectSpend: true)
    let key = try MutationJournalKey(
      namespace: "test", principal: principal.journalPrincipal, target: "act_1",
      operationID: descriptor.operationID, idempotencyKey: "anchor-required")
    XCTAssertThrowsError(
      try MutationApplyDependencies(
        authorization: MutationApplyAuthorization(
          descriptor: descriptor, journalKey: key, expectedPrincipal: principal, assetID: "act_1",
          requestedLiabilityCents: 0), journal: DurableMutationJournal(directory: directory),
        principalVerifier: StaticPrincipalVerifier(principal: principal),
        assetVerifier: FreshTestAssetVerifier(assetID: "act_1")))
  }

  func testDurableJournalCheckpointBeforeReplacementLeavesPriorDurableState() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "crash")
    let prepared = try DurableMutationJournal(directory: directory)
    try await prepared.prepare(key, digest: Self.journalDigest)
    let journal = try DurableMutationJournal(directory: directory) { point in
      if point == .beforeReplace { throw GraphValidationError.policyDenied }
    }
    await assertThrowsAsync(try await journal.transition(key, to: .inFlight))
    let reloaded = try DurableMutationJournal(directory: directory)
    let state = try await reloaded.state(for: key)
    XCTAssertEqual(state, .prepared)
  }

  func testDurableJournalCheckpointAfterReplacementRecoversNewDurableState() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try DurableMutationJournal.createNamespace(at: directory, namespace: "test")
    let key = try MutationJournalKey(
      namespace: "test", principal: "app:actor", target: "act_1", operationID: "meta.generic.write",
      idempotencyKey: "after-crash")
    let prepared = try DurableMutationJournal(directory: directory)
    try await prepared.prepare(key, digest: Self.journalDigest)
    let journal = try DurableMutationJournal(directory: directory) { point in
      if point == .afterReplace { throw GraphValidationError.policyDenied }
    }
    await assertThrowsAsync(try await journal.transition(key, to: .inFlight))
    let reloaded = try DurableMutationJournal(directory: directory)
    let state = try await reloaded.state(for: key)
    XCTAssertEqual(state, .inFlight)
  }

  func testSecureFileRejectsSymlink() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("request.json")
    let link = directory.appendingPathComponent("request-link.json")
    try Data("{\"value\":\"safe\"}".utf8).write(to: target)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    XCTAssertThrowsError(try SecureFile.read(FileProbe.self, from: link))
  }

  func testTypedReaderExtractsOnlyStructuredPagingCursor() async throws {
    let data = Data(
      "{\"data\":[{\"id\":\"1\"}],\"paging\":{\"cursors\":{\"after\":\"cursor-1\"}}}".utf8)
    let reader = try MetaAdsReader(
      reader: ResponseReader(response: try GraphResponse(status: 200, data: data)),
      version: GraphAPIVersion("v25.0"))
    let result = try await reader.adAccounts(
      try FieldSelection(["id"], domain: .adAccount), page: PageRequest())
    XCTAssertEqual(result.after?.value, "cursor-1")
  }

  func testTypedCatalogIsOfflineAndComplete() throws {
    let reader = try MetaAdsReader(reader: NeverReader(), version: GraphAPIVersion("v25.0"))
    XCTAssertEqual(reader.capabilities().operationIDs.count, 11)
    XCTAssertEqual(try AdAccountID("123").value, "act_123")
    XCTAssertThrowsError(try AdAccountID("１２３"))
    XCTAssertThrowsError(try FieldSelection(["fields"], domain: .campaign))
  }

  func testTolerantDomainRecordsPreserveUnknownProviderValuesAndFields() throws {
    let campaign = try JSONDecoder().decode(
      Campaign.self,
      from: Data(
        "{\"id\":\"1\",\"account_id\":\"act_1\",\"status\":\"FUTURE_PROVIDER_STATE\",\"budget_remaining\":12.34}"
          .utf8))
    XCTAssertEqual(campaign.record.id, "1")
    XCTAssertEqual(campaign.record.accountID, "act_1")
    XCTAssertEqual(campaign.record.status, .unknown("FUTURE_PROVIDER_STATE"))
    guard case .number = campaign.record.additionalFields["budget_remaining"]?.storage else {
      return XCTFail("unknown decimal field was not retained")
    }
  }

  func testFiltersAreBoundedAndEncodedWithoutRawFragments() throws {
    let encoded = try MetaAdsFilterEncoding.queryValue([
      MetaAdsFilter(field: "effective_status", operation: .in, value: .strings(["PAUSED"]))
    ])
    XCTAssertTrue(encoded.contains("effective_status"))
    XCTAssertThrowsError(
      try MetaAdsFilter(field: "status;drop", operation: .equal, value: .string("x")))
    XCTAssertThrowsError(
      try MetaAdsFilterEncoding.queryValue(
        Array(
          repeating: try MetaAdsFilter(field: "id", operation: .equal, value: .string("1")),
          count: 51)))
    let numeric = try MetaAdsFilterEncoding.queryValue([
      MetaAdsFilter(field: "id", operation: .equal, value: .integer(42))
    ])
    let decoded = try JSONSerialization.jsonObject(with: Data(numeric.utf8)) as? [[String: Any]]
    XCTAssertTrue(decoded?.first?["value"] is NSNumber)
  }

  func testReadBatchUsesOnlyGETRequestTypeAndRejectsDuplicateNames() throws {
    let version = try GraphAPIVersion("v26.0")
    let read = try GraphBatchItem(
      name: "first",
      request: ReaderGraphRequest(version: version, path: GraphPath(relative: "me")))
    XCTAssertNoThrow(try GraphReadBatch(items: [read]))
    let duplicate = try GraphBatchItem(name: "first", request: read.request)
    XCTAssertThrowsError(try GraphReadBatch(items: [read, duplicate]))
  }

  func testReadBatchEncodesOnlyValidatedRelativeRequestsAndDecodesPartialResults() throws {
    let version = try GraphAPIVersion("v26.0")
    let first = try GraphBatchItem(
      name: "first",
      request: ReaderGraphRequest(version: version, path: GraphPath(relative: "me")))
    let second = try GraphBatchItem(
      name: "second",
      request: ReaderGraphRequest(
        version: version, path: GraphPath(relative: "me/adaccounts"),
        query: GraphQuery([("fields", "id")])), dependsOn: ["first"])
    let batch = try GraphReadBatch(items: [first, second])
    let body = String(decoding: try batch.formBody(), as: UTF8.self)
    XCTAssertTrue(body.contains("relative_url"))
    XCTAssertFalse(body.contains("access_token"))
    XCTAssertThrowsError(
      try GraphReadBatch(items: [
        try GraphBatchItem(name: "cycle", request: first.request, dependsOn: ["cycle"])
      ]))
    let result = try GraphBatchResponse.decode(
      Data("[{\"code\":200,\"body\":\"{}\"},{\"code\":204}]".utf8), expectedCount: 2)
    XCTAssertEqual(result.map(\.status), [200, 204])
    XCTAssertTrue(result[1].omitted)
    let detailed = try GraphBatchResponse.decode(
      Data(
        "[{\"code\":400,\"body\":\"{\\\"error\\\":{\\\"code\\\":100,\\\"error_subcode\\\":2,\\\"message\\\":\\\"secret\\\"}}\",\"headers\":[{\"name\":\"x-fb-trace-id\",\"value\":\"trace\"}]}]"
          .utf8), expectedCount: 1)
    XCTAssertEqual(detailed[0].providerError?.code, 100)
    XCTAssertEqual(detailed[0].headers["x-fb-trace-id"], "trace")
  }

  func testReadExecutorRetriesReadsOnlyAndPaginatorDetectsCycles() async throws {
    let request = ReaderGraphRequest(
      version: try GraphAPIVersion("v26.0"), path: try GraphPath(relative: "me"))
    let transport = SequenceTransport(statuses: [500, 429, 200])
    let executor = GraphReadExecutor(
      transport: transport, sleeper: NoopSleeper(), randomness: MaximumRandomness(),
      policy: try GraphReadRetryPolicy(
        maxAttempts: 3, baseDelayNanoseconds: 1, maximumDelayNanoseconds: 2))
    let receipt = try await executor.execute(
      request, credential: ReaderGraphCredential(token: "TEST_ONLY_SENTINEL"))
    XCTAssertEqual(receipt.response.status, 200)
    XCTAssertEqual(receipt.attempts, 3)
    XCTAssertEqual(receipt.waitedNanoseconds, 3)
    let attempts = await transport.calls()
    XCTAssertEqual(attempts, 3)
    await assertThrowsAsync(
      try await GraphPaginator.collect(budget: try GraphPageBudget(maxPages: 3, maxItems: 3)) {
        request in
        let cursor = try PageCursor("repeat")
        if case .after = request.direction { return GraphPage(data: [1], after: cursor) }
        return GraphPage(data: [1], after: cursor)
      })
  }

  func testReadExecutorRecordsRetryEvidenceAndSharedThrottlePacesExecutors() async throws {
    let request = ReaderGraphRequest(
      version: try GraphAPIVersion("v26.0"), path: try GraphPath(relative: "me"))
    let events = RecordingEvents()
    let sleeper = RecordingSleeper()
    let throttle = try GraphReadThrottle(minimumIntervalNanoseconds: 10)
    let policy = try GraphReadRetryPolicy(
      maxAttempts: 2, baseDelayNanoseconds: 1, maximumDelayNanoseconds: 1,
      maximumTotalDelayNanoseconds: 10, maximumElapsedNanoseconds: 100)
    let retrying = GraphReadExecutor(
      transport: SequenceTransport(statuses: [500, 200]), sleeper: sleeper,
      randomness: MaximumRandomness(), policy: policy, clock: ConstantClock(), events: events)
    let receipt = try await retrying.execute(
      request, credential: ReaderGraphCredential(token: "sentinel"))
    XCTAssertTrue(receipt.events.contains { if case .retrying = $0 { true } else { false } })
    let first = GraphReadExecutor(
      transport: SuccessTransport(), sleeper: sleeper, policy: policy, clock: ConstantClock(),
      throttle: throttle)
    let second = GraphReadExecutor(
      transport: SuccessTransport(), sleeper: sleeper, policy: policy, clock: ConstantClock(),
      throttle: throttle)
    async let left = first.execute(request, credential: ReaderGraphCredential(token: "sentinel"))
    async let right = second.execute(request, credential: ReaderGraphCredential(token: "sentinel"))
    _ = try await (left, right)
    let waits = await sleeper.values()
    let recordedEvents = await events.values()
    XCTAssertTrue(waits.contains(10))
    XCTAssertTrue(recordedEvents.contains { if case .terminal = $0 { true } else { false } })
  }

  func testPaginatorRejectsUntrustedNegativeAndOversizedByteCounts() async throws {
    let budget = try GraphPageBudget(maxPages: 2, maxItems: 2, maxBytes: 10)
    await assertThrowsAsync(
      try await GraphPaginator.collect(budget: budget) { _ in
        GraphPage(data: [1], receivedBytes: -1)
      })
    await assertThrowsAsync(
      try await GraphPaginator.collect(budget: budget) { _ in
        GraphPage(data: [1], receivedBytes: Int.max)
      })
  }

  func testPaginatorUsesElapsedBudgetBeforeFetching() async throws {
    let budget = try GraphPageBudget(
      maxPages: 2, maxItems: 2, maxBytes: 10, maximumElapsedNanoseconds: 1)
    await assertThrowsAsync(
      try await GraphPaginator.collect(budget: budget, clock: SteppingClock(values: [0, 2])) { _ in
        XCTFail("must not fetch after elapsed budget")
        return GraphPage<Int>(data: [])
      })
  }

  func testPaginatorRejectsResponseThatFinishesAfterDeadline() async throws {
    let budget = try GraphPageBudget(
      maxPages: 2, maxItems: 2, maxBytes: 10, maximumElapsedNanoseconds: 1)
    await assertThrowsAsync(
      try await GraphPaginator.collect(budget: budget, clock: SteppingClock(values: [0, 0, 2])) {
        _ in
        GraphPage(data: [1])
      })
  }

  func testMultipartEncoderRevalidatesFileIdentity() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("fixture.txt")
    try Data("payload".utf8).write(to: fileURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    let file = try GraphUploadFile(url: fileURL, mediaType: "text/plain")
    let encoder = try GraphMultipartEncoder(parts: [
      try GraphMultipartPart(name: "caption", value: "safe"),
      try GraphMultipartPart(name: "source", file: file),
    ])
    let stream = try encoder.stream(maximumFileChunkBytes: 3)
    var encoded = Data()
    while let chunk = try stream.nextChunk() { encoded.append(chunk) }
    XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("payload"))
    try Data("replaced".utf8).write(to: fileURL)
    XCTAssertThrowsError(try file.read(offset: 0, maximumLength: 16))
  }

  func testMultipartStreamPullsFileChunksAndDedicatedUploadKeepsFixedGraphPath() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("fixture.txt")
    try Data("payload".utf8).write(to: fileURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    let encoder = try GraphMultipartEncoder(parts: [
      try GraphMultipartPart(
        name: "source", file: try GraphUploadFile(url: fileURL, mediaType: "text/plain"))
    ])
    let stream = try encoder.stream(maximumFileChunkBytes: 2)
    let first = try XCTUnwrap(stream.nextChunk())
    XCTAssertTrue(String(decoding: first, as: UTF8.self).contains("Content-Disposition"))
    XCTAssertEqual(try stream.nextChunk()?.count, 2)
    let transport = UploadTransport()
    let uploader = MetaGraphUploader(transport: transport, credentials: TestCredentials())
    let result = try await uploader.uploadForTesting(
      path: GraphPath(relative: "act_1/adimages"), version: GraphAPIVersion("v26.0"),
      encoder: encoder)
    XCTAssertEqual(result.status, 200)
    let paths = await transport.paths()
    XCTAssertEqual(paths, ["act_1/adimages"])
    XCTAssertTrue(URLSessionGraphTransport.isApprovedUploadPath("act_1/adimages"))
    XCTAssertFalse(URLSessionGraphTransport.isApprovedUploadPath("act_1/advideos"))
  }

  func testURLSessionMultipartUploadStreamsFileAndRejectsOversizedReceipt() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("fixture.txt")
    try Data("payload".utf8).write(to: fileURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    let encoder = try GraphMultipartEncoder(parts: [
      try GraphMultipartPart(
        name: "source", file: try GraphUploadFile(url: fileURL, mediaType: "text/plain"))
    ])
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UploadURLProtocol.self]
    let transport = URLSessionGraphTransport(configuration: configuration)

    UploadURLProtocol.recorder.configure(response: Data("{\"ok\":true}".utf8))
    let response = try await transport.uploadForTesting(
      path: GraphPath(relative: "act_1/adimages"), version: GraphAPIVersion("v26.0"),
      boundary: encoder.boundary, body: try encoder.stream(maximumFileChunkBytes: 2),
      credential: GraphCredential(token: "sentinel"))
    let record = UploadURLProtocol.recorder.snapshot()
    XCTAssertEqual(response.status, 200)
    XCTAssertEqual(record.requestCount, 1)
    XCTAssertTrue(record.usedBodyStream)
    XCTAssertEqual(record.authorization, "Bearer sentinel")
    XCTAssertTrue(String(decoding: record.body, as: UTF8.self).contains("payload"))

    UploadURLProtocol.recorder.configure(
      response: Data(repeating: 0x61, count: 4_194_305), holdOpen: true)
    await assertThrowsAsync(
      try await transport.uploadForTesting(
        path: GraphPath(relative: "act_1/adimages"), version: GraphAPIVersion("v26.0"),
        boundary: encoder.boundary, body: try encoder.stream(maximumFileChunkBytes: 2),
        credential: GraphCredential(token: "sentinel")))
    try await Task.sleep(for: .milliseconds(20))
    let oversized = UploadURLProtocol.recorder.snapshot()
    XCTAssertEqual(oversized.requestCount, 1)
    XCTAssertTrue(UploadURLProtocol.recorder.wasStopped())
  }

  func testTransportRejectsExternalRedirectsAndUsesEmptyEphemeralCredentialHandling() throws {
    let delegate = RejectingRedirectDelegate()
    let session = URLSession(configuration: .ephemeral)
    let task = session.dataTask(
      with: try XCTUnwrap(URL(string: "https://graph.facebook.com/v26.0/me")))
    let response = try XCTUnwrap(
      HTTPURLResponse(
        url: try XCTUnwrap(URL(string: "https://graph.facebook.com/v26.0/me")), statusCode: 302,
        httpVersion: nil, headerFields: ["Location": "https://attacker.invalid/"]))
    let callback = TransportDelegateCallback()
    delegate.urlSession(
      session, task: task, willPerformHTTPRedirection: response,
      newRequest: URLRequest(url: try XCTUnwrap(URL(string: "https://attacker.invalid/")))
    ) {
      callback.recordRedirect($0)
    }
    XCTAssertNil(callback.redirect())

    let protectionSpace = URLProtectionSpace(
      host: "graph.facebook.com", port: 443, protocol: "https", realm: nil,
      authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
    let challenge = URLAuthenticationChallenge(
      protectionSpace: protectionSpace, proposedCredential: nil, previousFailureCount: 0,
      failureResponse: nil, error: nil, sender: ChallengeSender())
    delegate.urlSession(session, task: task, didReceive: challenge) { disposition, _ in
      callback.recordDisposition(disposition)
    }
    XCTAssertEqual(callback.disposition(), .performDefaultHandling)

    let trustSpace = URLProtectionSpace(
      host: "graph.facebook.com", port: 443, protocol: "https", realm: nil,
      authenticationMethod: NSURLAuthenticationMethodServerTrust)
    let trustChallenge = URLAuthenticationChallenge(
      protectionSpace: trustSpace, proposedCredential: nil, previousFailureCount: 0,
      failureResponse: nil, error: nil, sender: ChallengeSender())
    let trustCallback = TransportDelegateCallback()
    delegate.urlSession(session, task: task, didReceive: trustChallenge) { disposition, _ in
      trustCallback.recordDisposition(disposition)
    }
    XCTAssertEqual(trustCallback.disposition(), .performDefaultHandling)
  }

  func testTerminalTransportFailureEmitsEvidence() async throws {
    let events = RecordingEvents()
    let executor = GraphReadExecutor(
      transport: FailingTransport(), policy: try GraphReadRetryPolicy(maxAttempts: 1),
      events: events)
    await assertThrowsAsync(
      try await executor.execute(
        ReaderGraphRequest(
          version: try GraphAPIVersion("v26.0"), path: try GraphPath(relative: "me")),
        credential: ReaderGraphCredential(token: "sentinel")))
    let recorded = await events.values()
    XCTAssertTrue(
      recorded.contains { event in
        if case .terminal(_, status: nil) = event { return true }
        return false
      })
  }

  func testTypedCommandRejectsMalformedOrInapplicableFlagsBeforeCredentials() async {
    let malformed = await ReaderCLI.run(arguments: [
      "ads", "list", "campaigns", "--api-version", "v26.0", "--account", "act_1", "--fields", "id",
      "--limit", "bad",
    ])
    XCTAssertEqual(malformed, 2)
    let inapplicable = await ReaderCLI.run(arguments: [
      "ads", "list", "campaigns", "--api-version", "v26.0", "--account", "act_1", "--fields", "id",
      "--path", "ignored",
    ])
    XCTAssertEqual(inapplicable, 2)
    let unknownSubject = await ReaderCLI.run(arguments: [
      "ads", "insights", "unknown", "--api-version", "v26.0", "--path", "act_1", "--fields",
      "spend",
    ])
    XCTAssertEqual(unknownSubject, 2)
    let mismatchedSubject = await ReaderCLI.run(arguments: [
      "ads", "insights", "account", "--api-version", "v26.0", "--path", "123", "--fields", "spend",
    ])
    XCTAssertEqual(mismatchedSubject, 2)
  }

  func testTypedAdAccountListRejectsInapplicableAccountFlagBeforeCredentials() async {
    let result = await ReaderCLI.run(arguments: [
      "ads", "list", "adaccounts", "--api-version", "v26.0", "--account", "act_1", "--fields",
      "id",
    ])
    XCTAssertEqual(result, 2)
  }

  func testInsightSubjectBindsOperationToExactObjectPathShape() throws {
    XCTAssertNoThrow(
      try MetaAdsInsightSubject.account.validate(path: GraphPath(relative: "act_1")))
    XCTAssertNoThrow(
      try MetaAdsInsightSubject.campaign.validate(path: GraphPath(relative: "123")))
    XCTAssertThrowsError(
      try MetaAdsInsightSubject.account.validate(path: GraphPath(relative: "123")))
    XCTAssertThrowsError(
      try MetaAdsInsightSubject.ad.validate(path: GraphPath(relative: "act_1")))
  }

  func testProgrammaticStringArrayFilterValidatesEachMember() throws {
    XCTAssertThrowsError(
      try MetaAdsFilter(
        field: "status", operation: .in, value: .strings(["safe", "bad\nmember"])))
  }

  func testBatchReaderUsesOnlyTheDedicatedReadBatchCapability() async throws {
    let request = ReaderGraphRequest(
      version: try GraphAPIVersion("v26.0"), path: try GraphPath(relative: "me"))
    let batch = try GraphReadBatch(items: [GraphBatchItem(name: "me", request: request)])
    let transport = BatchTransport()
    let reader = MetaGraphReader(transport: transport, credentials: ReaderTestCredentials())
    let results = try await reader.get(batch: batch)
    XCTAssertEqual(results.first?.status, 200)
    let calls = await transport.batchCalls()
    XCTAssertEqual(calls, 1)
  }

  func testTypedOptionsBindFilteringAndInsightMetricsWithoutLossyStrings() async throws {
    let response = try GraphResponse(
      status: 200,
      data: Data(
        "{\"data\":[{\"account_id\":\"act_1\",\"spend\":12.34,\"actions\":[{\"value\":\"7\"}]}]}"
          .utf8))
    let capture = CapturingReader(response: response)
    let ads = try MetaAdsReader(reader: capture, version: GraphAPIVersion("v25.0"))
    let fields = try FieldSelection(["id"], domain: .campaign)
    let options = try MetaAdsListOptions(
      fields: fields,
      filters: [MetaAdsFilter(field: "id", operation: .equal, value: .integer(42))])
    _ = try await ads.campaigns(try AdAccountID("1"), options: options)
    let capturedQuery = await capture.lastQuery()
    XCTAssertEqual(capturedQuery?.items.first?.0, "fields")
    XCTAssertEqual(capturedQuery?.items.dropFirst().first?.0, "filtering")
    let insightFields = try FieldSelection(["spend", "actions"], domain: .insight)
    let rows = try await ads.insights(
      path: GraphPath(relative: "act_1"), fields: insightFields, page: PageRequest())
    guard case .number = rows.data[0].metrics["spend"]?.storage else {
      return XCTFail("numeric metric was not retained")
    }
    guard case .array = rows.data[0].metrics["actions"]?.storage else {
      return XCTFail("action array was not retained")
    }
  }

}

private struct TestCredentials: GraphCredentialResolving {
  func resolve() throws -> GraphCredential { GraphCredential(token: "TEST_ONLY_SENTINEL") }
}

private struct ReaderTestCredentials: ReaderGraphCredentialResolving {
  func resolve() throws -> ReaderGraphCredential {
    ReaderGraphCredential(token: "TEST_ONLY_SENTINEL")
  }
}

private final class CountingCredentials: GraphCredentialResolving, @unchecked Sendable {
  private let lock = NSLock()
  private var callCount = 0
  func resolve() throws -> GraphCredential {
    lock.lock()
    defer { lock.unlock() }
    callCount += 1
    return GraphCredential(token: "TEST_ONLY_SENTINEL")
  }
  func calls() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return callCount
  }
}

private struct StaticPrincipalVerifier: MutationPrincipalVerifying {
  let principal: ProviderPrincipalEvidence
  func verify(credential: GraphCredential) async throws -> ProviderPrincipalEvidence { principal }
}

private struct FreshTestAssetVerifier: MutationAssetVerifying {
  let assetID: String
  func verify(assetID: String, credential: GraphCredential) async throws
    -> VerifiedTestAssetEvidence
  {
    try VerifiedTestAssetEvidence(
      assetID: self.assetID, providerVerifiedAt: Date(), nonBillable: true)
  }
}

private struct StaticAssetVerifier: MutationAssetVerifying {
  let evidence: VerifiedTestAssetEvidence
  func verify(assetID: String, credential: GraphCredential) async throws
    -> VerifiedTestAssetEvidence
  {
    evidence
  }
}

private final class FailingOnceCredentials: GraphCredentialResolving, @unchecked Sendable {
  private let lock = NSLock()
  private var attempts = 0
  func resolve() throws -> GraphCredential {
    lock.lock()
    defer { lock.unlock() }
    attempts += 1
    guard attempts > 1 else { throw GraphValidationError.missingCredential }
    return GraphCredential(token: "TEST_ONLY_SENTINEL")
  }
}

private struct StaticReconciler: MutationReconciling {
  let result: MutationReconciliationState
  func reconcile(
    descriptor: MutationDescriptor, path: GraphPath, credential: GraphCredential
  ) async throws -> MutationReconciliationState { result }
}

private actor CountingReconciler: MutationReconciling {
  private var count = 0
  func reconcile(
    descriptor: MutationDescriptor, path: GraphPath, credential: GraphCredential
  ) async throws -> MutationReconciliationState {
    count += 1
    return .pending
  }
  func calls() -> Int { count }
}

private actor RecordingMutationTransport: GraphTransport {
  private let status: Int
  private var callCount = 0
  init(status: Int) { self.status = status }
  func send(_ request: GraphRequest, credential: GraphCredential) async throws -> GraphResponse {
    callCount += 1
    return try GraphResponse(status: status, data: Data("receipt".utf8))
  }
  func calls() -> Int { callCount }
}

private final class UploadURLProtocolRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var response = Data()
  private var requests = 0
  private var body = Data()
  private var bodyStream = false
  private var authorization: String?
  private var contentType: String?
  private var holdOpen = false
  private var stopped = false

  func configure(response: Data, holdOpen: Bool = false) {
    lock.lock()
    defer { lock.unlock() }
    self.response = response
    requests = 0
    body = Data()
    bodyStream = false
    authorization = nil
    contentType = nil
    self.holdOpen = holdOpen
    stopped = false
  }

  func record(request: URLRequest) -> Data {
    var captured = Data()
    if let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4_096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else { break }
        if count == 0 { break }
        captured.append(buffer, count: count)
      }
    } else {
      captured = request.httpBody ?? Data()
    }
    lock.lock()
    defer { lock.unlock() }
    requests += 1
    body = captured
    bodyStream = request.httpBodyStream != nil
    authorization = request.value(forHTTPHeaderField: "Authorization")
    contentType = request.value(forHTTPHeaderField: "Content-Type")
    return response
  }

  func snapshot() -> (
    requestCount: Int, body: Data, usedBodyStream: Bool, authorization: String?,
    contentType: String?
  ) {
    lock.lock()
    defer { lock.unlock() }
    return (requests, body, bodyStream, authorization, contentType)
  }

  func shouldHoldOpen() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return holdOpen
  }
  func recordStop() {
    lock.lock()
    defer { lock.unlock() }
    stopped = true
  }
  func wasStopped() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return stopped
  }
}

private final class TransportDelegateCallback: @unchecked Sendable {
  private let lock = NSLock()
  private var redirectRequest: URLRequest?
  private var authDisposition: URLSession.AuthChallengeDisposition?

  func recordRedirect(_ request: URLRequest?) {
    lock.lock()
    defer { lock.unlock() }
    redirectRequest = request
  }
  func redirect() -> URLRequest? {
    lock.lock()
    defer { lock.unlock() }
    return redirectRequest
  }
  func recordDisposition(_ disposition: URLSession.AuthChallengeDisposition) {
    lock.lock()
    defer { lock.unlock() }
    authDisposition = disposition
  }
  func disposition() -> URLSession.AuthChallengeDisposition? {
    lock.lock()
    defer { lock.unlock() }
    return authDisposition
  }
}

private final class ChallengeSender: NSObject, URLAuthenticationChallengeSender {
  func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
  func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
  func cancel(_ challenge: URLAuthenticationChallenge) {}
  func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
  func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}

private final class UploadURLProtocol: URLProtocol, @unchecked Sendable {
  static let recorder = UploadURLProtocolRecorder()

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let responseData = Self.recorder.record(request: request)
    guard let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: responseData)
    if Self.recorder.shouldHoldOpen() {
      DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
        guard let self else { return }
        self.client?.urlProtocolDidFinishLoading(self)
      }
    } else {
      client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() { Self.recorder.recordStop() }
}

private struct NeverTransport: GraphTransport {
  func send(_ request: GraphRequest, credential: GraphCredential) async throws -> GraphResponse {
    XCTFail("unexpected transport")
    throw GraphValidationError.invalidRequest
  }
}
private struct NeverReader: MetaGraphReading {
  func get(path: GraphPath, version: GraphAPIVersion, query: GraphQuery) async throws
    -> GraphResponse
  {
    XCTFail("unexpected transport")
    throw GraphValidationError.invalidRequest
  }
}

private struct ResponseReader: MetaGraphReading {
  let response: GraphResponse
  func get(path: GraphPath, version: GraphAPIVersion, query: GraphQuery) async throws
    -> GraphResponse
  {
    response
  }
}

private actor SequenceTransport: GraphTransport, ReaderGraphTransport {
  private var statuses: [Int]
  private var count = 0
  init(statuses: [Int]) { self.statuses = statuses }
  func send(_ request: GraphRequest, credential: GraphCredential) async throws -> GraphResponse {
    count += 1
    return try GraphResponse(status: statuses.removeFirst(), data: Data())
  }
  func send(_ request: ReaderGraphRequest, credential: ReaderGraphCredential) async throws
    -> GraphResponse
  {
    count += 1
    return try GraphResponse(status: statuses.removeFirst(), data: Data())
  }
  func calls() -> Int { count }
}

private actor InMemoryTrustedHeadClient: TrustedHeadClient {
  private var heads: [String: TrustedHead] = [:]
  private var compareAndSetCallCount = 0

  func readHead(namespace: String, recordIdentity: String) async throws -> TrustedHead? {
    heads["\(namespace):\(recordIdentity)"]
  }

  func compareAndSetHead(
    namespace: String, recordIdentity: String, expected: TrustedHead?, proposed: TrustedHead
  ) async throws -> Bool {
    compareAndSetCallCount += 1
    let key = "\(namespace):\(recordIdentity)"
    guard heads[key] == expected else { return false }
    heads[key] = proposed
    return true
  }

  func sequence() -> UInt64? { heads.values.first?.sequence }
  func compareAndSetCalls() -> Int { compareAndSetCallCount }
}

private struct NoopSleeper: GraphSleeping {
  func sleep(nanoseconds: UInt64) async throws {}
}

private actor RecordingSleeper: GraphSleeping {
  private var recorded: [UInt64] = []
  func sleep(nanoseconds: UInt64) async throws { recorded.append(nanoseconds) }
  func values() -> [UInt64] { recorded }
}

private actor RecordingEvents: GraphReadEventSink {
  private var recorded: [GraphReadEvent] = []
  func record(_ event: GraphReadEvent) async { recorded.append(event) }
  func values() -> [GraphReadEvent] { recorded }
}

private struct MaximumRandomness: GraphRandomness {
  func uniform(upperBound: UInt64) -> UInt64 { upperBound }
}

private final class SteppingClock: GraphReadClock, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [UInt64]
  init(values: [UInt64]) { self.values = values }
  func nowNanoseconds() -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    return values.count > 1 ? values.removeFirst() : values[0]
  }
}

private final class SteppingDateClock: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Date]
  init(values: [Date]) { self.values = values }
  func now() -> Date {
    lock.lock()
    defer { lock.unlock() }
    return values.count > 1 ? values.removeFirst() : values[0]
  }
}

private struct ConstantClock: GraphReadClock {
  func nowNanoseconds() -> UInt64 { 0 }
}

private struct SuccessTransport: GraphTransport, ReaderGraphTransport {
  func send(_ request: GraphRequest, credential: GraphCredential) async throws -> GraphResponse {
    try GraphResponse(status: 200, data: Data())
  }
  func send(_ request: ReaderGraphRequest, credential: ReaderGraphCredential) async throws
    -> GraphResponse
  {
    try GraphResponse(status: 200, data: Data())
  }
}

private struct FailingTransport: GraphTransport, ReaderGraphTransport {
  func send(_ request: GraphRequest, credential: GraphCredential) async throws -> GraphResponse {
    throw URLError(.badServerResponse)
  }
  func send(_ request: ReaderGraphRequest, credential: ReaderGraphCredential) async throws
    -> GraphResponse
  {
    throw URLError(.badServerResponse)
  }
}

private actor UploadTransport: GraphMultipartUploading {
  private var uploadedPaths: [String] = []
  func upload(
    path: GraphPath, version: GraphAPIVersion, boundary: String, body: GraphMultipartBodyStream,
    credential: GraphCredential
  ) async throws -> GraphResponse {
    uploadedPaths.append(path.description)
    while try body.nextChunk() != nil {}
    return try GraphResponse(status: 200, data: Data())
  }
  func paths() -> [String] { uploadedPaths }
}

private actor BatchTransport: GraphTransport, ReaderGraphTransport, GraphReadBatchExecuting {
  private var calls = 0
  func send(_ request: GraphRequest, credential: GraphCredential) async throws -> GraphResponse {
    XCTFail("unexpected ordinary request")
    throw GraphValidationError.invalidRequest
  }
  func send(_ request: ReaderGraphRequest, credential: ReaderGraphCredential) async throws
    -> GraphResponse
  {
    XCTFail("unexpected ordinary request")
    throw GraphValidationError.invalidRequest
  }
  func send(batch: GraphReadBatch, credential: ReaderGraphCredential) async throws
    -> [GraphBatchResult]
  {
    calls += 1
    return [GraphBatchResult(status: 200, body: Data("{}".utf8), omitted: false)]
  }
  func batchCalls() -> Int { calls }
}

private actor CapturingReader: MetaGraphReading {
  let response: GraphResponse
  private var query: GraphQuery?
  init(response: GraphResponse) { self.response = response }
  func get(path: GraphPath, version: GraphAPIVersion, query: GraphQuery) async throws
    -> GraphResponse
  {
    self.query = query
    return response
  }
  func lastQuery() -> GraphQuery? { query }
}

private struct FileProbe: Codable { let value: String }

private func trustedHeadExpectation(from journalDirectory: URL, trustedHeadData: Data) throws
  -> TrustedHeadRecoveryExpectation
{
  let record = try XCTUnwrap(
    try FileManager.default.contentsOfDirectory(
      at: journalDirectory, includingPropertiesForKeys: nil
    )
    .first { $0.pathExtension == "json" })
  let object = try XCTUnwrap(
    try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
  let events = try XCTUnwrap(object["events"] as? [[String: Any]])
  let event = try XCTUnwrap(events.last)
  let recordIdentity = try XCTUnwrap(object["recordIdentity"] as? String)
  let firstRetainedSequence = try XCTUnwrap(
    (object["firstRetainedSequence"] as? NSNumber)?.uint64Value)
  let previousRetainedHash = object["previousRetainedHash"] as? String
  let sequence = try XCTUnwrap((event["sequence"] as? NSNumber)?.uint64Value)
  let hash = try XCTUnwrap(event["hash"] as? String)
  let anchor = try XCTUnwrap(
    try JSONSerialization.jsonObject(with: trustedHeadData) as? [String: Any])
  let anchoredFirstRetainedSequence = try XCTUnwrap(
    (anchor["firstRetainedSequence"] as? NSNumber)?.uint64Value)
  let anchoredPreviousRetainedHash = anchor["previousRetainedHash"] as? String
  let anchoredSequence = try XCTUnwrap((anchor["sequence"] as? NSNumber)?.uint64Value)
  let anchoredHash = try XCTUnwrap(anchor["hash"] as? String)
  return try TrustedHeadRecoveryExpectation(
    recordIdentity: recordIdentity, firstRetainedSequence: firstRetainedSequence,
    previousRetainedHash: previousRetainedHash, sequence: sequence, hash: hash,
    anchoredFirstRetainedSequence: anchoredFirstRetainedSequence,
    anchoredPreviousRetainedHash: anchoredPreviousRetainedHash, anchoredSequence: anchoredSequence,
    anchoredHash: anchoredHash)
}

private func assertThrowsAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("expected error", file: file, line: line)
  } catch {}
}
