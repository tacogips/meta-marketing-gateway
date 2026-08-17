import Foundation
import MetaGraphPrimitives

public struct AdAccountID: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
  public let value: String
  public init(_ value: String) throws {
    let digits = value.hasPrefix("act_") ? String(value.dropFirst(4)) : value
    guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else {
      throw GraphValidationError.invalidIdentifier
    }
    self.value = "act_\(digits)"
  }
  public var description: String { value }
}

public struct CampaignID: Sendable, Equatable, Hashable, Codable {
  public let value: String
  public init(_ value: String) throws {
    try Self.valid(value)
    self.value = value
  }
  private static func valid(_ value: String) throws {
    guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }) else {
      throw GraphValidationError.invalidIdentifier
    }
  }
}
public struct AdSetID: Sendable, Equatable, Hashable, Codable {
  public let value: String
  public init(_ value: String) throws {
    _ = try CampaignID(value)
    self.value = value
  }
}
public struct AdID: Sendable, Equatable, Hashable, Codable {
  public let value: String
  public init(_ value: String) throws {
    _ = try CampaignID(value)
    self.value = value
  }
}
public struct AdCreativeID: Sendable, Equatable, Hashable, Codable {
  public let value: String
  public init(_ value: String) throws {
    _ = try CampaignID(value)
    self.value = value
  }
}

public enum MetaAdsDomain: String, Sendable, CaseIterable {
  case adAccount, campaign, adSet, ad, adCreative, insight
}

/// The reviewed, versioned typed-field matrix is deliberately the single
/// authority used by request validation and local capability discovery.  Callers
/// needing a provider field outside this conservative matrix must use the safe
/// generic reader instead of smuggling an expression through typed routes.
public enum MetaAdsFieldMatrix {
  /// The typed matrix is pinned to the official reference pages reviewed on
  /// 2026-08-15. Generic GET may use another validated Graph version but does
  /// not inherit typed-field compatibility claims.
  public static let reviewedVersion = "v25.0"

  public static func fields(for domain: MetaAdsDomain) -> [String] {
    switch domain {
    case .adAccount:
      [
        "id", "account_id", "name", "account_status", "currency", "timezone_name",
        "business_name", "created_time",
      ]
    case .campaign:
      [
        "id", "account_id", "name", "objective", "status", "effective_status", "buying_type",
        "start_time", "stop_time", "created_time", "updated_time",
      ]
    case .adSet:
      [
        "id", "account_id", "campaign_id", "name", "status", "effective_status",
        "optimization_goal", "billing_event", "start_time", "end_time", "created_time",
        "updated_time",
      ]
    case .ad:
      [
        "id", "account_id", "campaign_id", "adset_id", "name", "status", "effective_status",
        "creative", "created_time", "updated_time",
      ]
    case .adCreative:
      [
        "id", "account_id", "name", "title", "body", "status", "thumbnail_url", "object_story_id",
        "created_time",
      ]
    case .insight:
      [
        "account_id", "campaign_id", "adset_id", "ad_id", "date_start", "date_stop",
        "impressions", "clicks", "spend", "actions",
      ]
    }
  }
}

/// Closed insight subjects bind a CLI subject token to both its operation and
/// the only Graph object-path shape it may address.
public enum MetaAdsInsightSubject: String, Sendable, CaseIterable {
  case account, campaign
  case adSet = "adset"
  case ad

  public var operationID: String { "meta.ads.insights.read" }

  public func validate(path: GraphPath) throws {
    let value = path.description
    let valid: Bool =
      switch self {
      case .account: value.wholeMatch(of: /act_[0-9]+/) != nil
      case .campaign, .adSet, .ad: value.wholeMatch(of: /[0-9]+/) != nil
      }
    guard valid, MetaAdsCapabilityCatalog.operationIDs.contains(operationID) else {
      throw GraphValidationError.invalidRequest
    }
  }
}
public struct FieldSelection: Sendable, Equatable {
  public let fields: [String]
  public init(_ fields: [String], domain: MetaAdsDomain) throws {
    let permitted = Set(MetaAdsFieldMatrix.fields(for: domain))
    let unique = fields.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    guard !unique.isEmpty, unique.joined(separator: ",").utf8.count <= 16_384,
      unique.allSatisfy(permitted.contains)
    else { throw GraphValidationError.invalidRequest }
    self.fields = unique
  }
  public var encoded: String { fields.joined(separator: ",") }
}

public struct JSONValue: Sendable, Codable, Equatable {
  public enum Storage: Sendable, Equatable {
    case string(String)
    case number(String)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])
  }
  public let storage: Storage
  public init(storage: Storage) { self.storage = storage }
  public init(from decoder: Decoder) throws {
    let single = try decoder.singleValueContainer()
    if single.decodeNil() {
      storage = .null
    } else if let value = try? single.decode(Bool.self) {
      storage = .bool(value)
    } else if let value = try? single.decode(String.self) {
      storage = .string(value)
    } else if let value = try? single.decode(Decimal.self) {
      storage = .number(NSDecimalNumber(decimal: value).stringValue)
    } else if let value = try? single.decode([JSONValue].self) {
      storage = .array(value)
    } else {
      storage = .object(try single.decode([String: JSONValue].self))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var single = encoder.singleValueContainer()
    switch storage {
    case .string(let value): try single.encode(value)
    case .number(let value):
      guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
        throw GraphValidationError.invalidRequest
      }
      try single.encode(decimal)
    case .bool(let value): try single.encode(value)
    case .null: try single.encodeNil()
    case .array(let value): try single.encode(value)
    case .object(let value): try single.encode(value)
    }
  }
}

public struct MetaAdsObject: Sendable, Codable, Equatable {
  public let id: String?
  public let name: String?
  public let additionalFields: [String: JSONValue]
  public init(id: String?, name: String?, additionalFields: [String: JSONValue]) {
    self.id = id
    self.name = name
    self.additionalFields = additionalFields
  }
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AnyCodingKey.self)
    id = try container.decodeIfPresent(String.self, forKey: .init("id"))
    name = try container.decodeIfPresent(String.self, forKey: .init("name"))
    var extra: [String: JSONValue] = [:]
    for key in container.allKeys where key.stringValue != "id" && key.stringValue != "name" {
      extra[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
    }
    additionalFields = extra
  }
}

/// Insight rows intentionally retain every provider metric as a JSON value. This
/// avoids lossy conversion of decimal strings, action arrays, and future metrics.
public struct InsightRow: Sendable, Codable, Equatable {
  public let accountID: String?
  public let campaignID: String?
  public let adSetID: String?
  public let adID: String?
  public let dateStart: String?
  public let dateStop: String?
  public let metrics: [String: JSONValue]

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: AnyCodingKey.self)
    accountID = try c.decodeIfPresent(String.self, forKey: .init("account_id"))
    campaignID = try c.decodeIfPresent(String.self, forKey: .init("campaign_id"))
    adSetID = try c.decodeIfPresent(String.self, forKey: .init("adset_id"))
    adID = try c.decodeIfPresent(String.self, forKey: .init("ad_id"))
    dateStart = try c.decodeIfPresent(String.self, forKey: .init("date_start"))
    dateStop = try c.decodeIfPresent(String.self, forKey: .init("date_stop"))
    let dimensions: Set<String> = [
      "account_id", "campaign_id", "adset_id", "ad_id", "date_start", "date_stop",
    ]
    metrics = try Dictionary(
      uniqueKeysWithValues: c.allKeys.filter { !dimensions.contains($0.stringValue) }.map {
        ($0.stringValue, try c.decode(JSONValue.self, forKey: $0))
      })
  }
}

public struct GraphPage<Item: Sendable>: Sendable {
  public let data: [Item]
  public let after: PageCursor?
  public let receivedBytes: Int
  public init(data: [Item], after: PageCursor? = nil, receivedBytes: Int = 0) {
    self.data = data
    self.after = after
    self.receivedBytes = receivedBytes
  }
}

public struct MetaAdsListOptions: Sendable, Equatable {
  public let fields: FieldSelection
  public let filters: [MetaAdsFilter]
  public let page: PageRequest

  public init(
    fields: FieldSelection, filters: [MetaAdsFilter] = [], page: PageRequest = try! PageRequest()
  ) throws {
    _ = try MetaAdsFilterEncoding.queryValue(filters)
    self.fields = fields
    self.filters = filters
    self.page = page
  }
}
public struct CapabilityDocument: Sendable, Codable {
  public let effectiveVersion: String
  public let schemaReviewDate: String
  public let operationIDs: [String]
}

public protocol MetaAdsReading: Sendable {
  func adAccounts(_ fields: FieldSelection, page: PageRequest) async throws -> GraphPage<AdAccount>
  func adAccount(_ id: AdAccountID, fields: FieldSelection) async throws -> AdAccount
  func campaigns(_ account: AdAccountID, fields: FieldSelection, page: PageRequest) async throws
    -> GraphPage<Campaign>
  func campaign(_ id: CampaignID, fields: FieldSelection) async throws -> Campaign
  func adSets(_ account: AdAccountID, fields: FieldSelection, page: PageRequest) async throws
    -> GraphPage<AdSet>
  func adSet(_ id: AdSetID, fields: FieldSelection) async throws -> AdSet
  func ads(_ account: AdAccountID, fields: FieldSelection, page: PageRequest) async throws
    -> GraphPage<Ad>
  func ad(_ id: AdID, fields: FieldSelection) async throws -> Ad
  func adCreatives(_ account: AdAccountID, fields: FieldSelection, page: PageRequest) async throws
    -> GraphPage<AdCreative>
  func adCreative(_ id: AdCreativeID, fields: FieldSelection) async throws -> AdCreative
  func insights(path: GraphPath, fields: FieldSelection, page: PageRequest) async throws
    -> GraphPage<InsightRow>
  func capabilities() -> CapabilityDocument
}

public struct MetaAdsReader: MetaAdsReading {
  private let reader: any MetaGraphReading
  private let version: GraphAPIVersion
  public init(reader: any MetaGraphReading, version: GraphAPIVersion) throws {
    guard version.description == MetaAdsFieldMatrix.reviewedVersion else {
      throw GraphValidationError.invalidAPIVersion
    }
    self.reader = reader
    self.version = version
  }
  public func adAccounts(_ fields: FieldSelection, page: PageRequest) async throws -> GraphPage<
    AdAccount
  > { try await list("me/adaccounts", fields, page, filters: [], as: AdAccount.self) }
  public func adAccounts(_ options: MetaAdsListOptions) async throws -> GraphPage<AdAccount> {
    try await list(
      "me/adaccounts", options.fields, options.page, filters: options.filters, as: AdAccount.self)
  }
  public func allAdAccounts(
    _ options: MetaAdsListOptions, budget: GraphPageBudget = try! GraphPageBudget(),
    clock: any GraphReadClock = SystemGraphReadClock()
  ) async throws -> [AdAccount] {
    try await GraphPaginator.collect(initial: options.page, budget: budget, clock: clock) { page in
      try await list(
        "me/adaccounts", options.fields, page, filters: options.filters, as: AdAccount.self)
    }
  }
  public func adAccount(_ id: AdAccountID, fields: FieldSelection) async throws -> AdAccount {
    try await one(id.value, fields, as: AdAccount.self)
  }
  public func campaigns(_ account: AdAccountID, fields: FieldSelection, page: PageRequest)
    async throws -> GraphPage<Campaign>
  { try await list("\(account.value)/campaigns", fields, page, filters: [], as: Campaign.self) }
  public func campaigns(_ account: AdAccountID, options: MetaAdsListOptions) async throws
    -> GraphPage<Campaign>
  {
    try await list(
      "\(account.value)/campaigns", options.fields, options.page, filters: options.filters,
      as: Campaign.self)
  }
  public func allCampaigns(
    _ account: AdAccountID, options: MetaAdsListOptions,
    budget: GraphPageBudget = try! GraphPageBudget(),
    clock: any GraphReadClock = SystemGraphReadClock()
  ) async throws -> [Campaign] {
    try await GraphPaginator.collect(initial: options.page, budget: budget, clock: clock) { page in
      try await list(
        "\(account.value)/campaigns", options.fields, page, filters: options.filters,
        as: Campaign.self)
    }
  }
  public func campaign(_ id: CampaignID, fields: FieldSelection) async throws -> Campaign {
    try await one(id.value, fields, as: Campaign.self)
  }
  public func adSets(_ account: AdAccountID, fields: FieldSelection, page: PageRequest) async throws
    -> GraphPage<AdSet>
  { try await list("\(account.value)/adsets", fields, page, filters: [], as: AdSet.self) }
  public func adSets(_ account: AdAccountID, options: MetaAdsListOptions) async throws -> GraphPage<
    AdSet
  > {
    try await list(
      "\(account.value)/adsets", options.fields, options.page, filters: options.filters,
      as: AdSet.self)
  }
  public func allAdSets(
    _ account: AdAccountID, options: MetaAdsListOptions,
    budget: GraphPageBudget = try! GraphPageBudget(),
    clock: any GraphReadClock = SystemGraphReadClock()
  ) async throws -> [AdSet] {
    try await GraphPaginator.collect(initial: options.page, budget: budget, clock: clock) { page in
      try await list(
        "\(account.value)/adsets", options.fields, page, filters: options.filters, as: AdSet.self)
    }
  }
  public func adSet(_ id: AdSetID, fields: FieldSelection) async throws -> AdSet {
    try await one(id.value, fields, as: AdSet.self)
  }
  public func ads(_ account: AdAccountID, fields: FieldSelection, page: PageRequest) async throws
    -> GraphPage<Ad>
  { try await list("\(account.value)/ads", fields, page, filters: [], as: Ad.self) }
  public func ads(_ account: AdAccountID, options: MetaAdsListOptions) async throws -> GraphPage<Ad>
  {
    try await list(
      "\(account.value)/ads", options.fields, options.page, filters: options.filters, as: Ad.self)
  }
  public func allAds(
    _ account: AdAccountID, options: MetaAdsListOptions,
    budget: GraphPageBudget = try! GraphPageBudget(),
    clock: any GraphReadClock = SystemGraphReadClock()
  ) async throws -> [Ad] {
    try await GraphPaginator.collect(initial: options.page, budget: budget, clock: clock) { page in
      try await list(
        "\(account.value)/ads", options.fields, page, filters: options.filters, as: Ad.self)
    }
  }
  public func ad(_ id: AdID, fields: FieldSelection) async throws -> Ad {
    try await one(id.value, fields, as: Ad.self)
  }
  public func adCreatives(_ account: AdAccountID, fields: FieldSelection, page: PageRequest)
    async throws -> GraphPage<AdCreative>
  { try await list("\(account.value)/adcreatives", fields, page, filters: [], as: AdCreative.self) }
  public func adCreatives(_ account: AdAccountID, options: MetaAdsListOptions) async throws
    -> GraphPage<AdCreative>
  {
    try await list(
      "\(account.value)/adcreatives", options.fields, options.page, filters: options.filters,
      as: AdCreative.self)
  }
  public func allAdCreatives(
    _ account: AdAccountID, options: MetaAdsListOptions,
    budget: GraphPageBudget = try! GraphPageBudget(),
    clock: any GraphReadClock = SystemGraphReadClock()
  ) async throws -> [AdCreative] {
    try await GraphPaginator.collect(initial: options.page, budget: budget, clock: clock) { page in
      try await list(
        "\(account.value)/adcreatives", options.fields, page, filters: options.filters,
        as: AdCreative.self)
    }
  }
  public func adCreative(_ id: AdCreativeID, fields: FieldSelection) async throws -> AdCreative {
    try await one(id.value, fields, as: AdCreative.self)
  }
  public func insights(path: GraphPath, fields: FieldSelection, page: PageRequest) async throws
    -> GraphPage<InsightRow>
  { try await insightList("\(path.description)/insights", fields, page, filters: []) }
  public func insights(path: GraphPath, options: MetaAdsListOptions) async throws -> GraphPage<
    InsightRow
  > {
    try await insightList(
      "\(path.description)/insights", options.fields, options.page, filters: options.filters)
  }
  public func allInsights(
    path: GraphPath, options: MetaAdsListOptions,
    budget: GraphPageBudget = try! GraphPageBudget(),
    clock: any GraphReadClock = SystemGraphReadClock()
  ) async throws -> [InsightRow] {
    try await GraphPaginator.collect(initial: options.page, budget: budget, clock: clock) { page in
      try await insightList(
        "\(path.description)/insights", options.fields, page, filters: options.filters)
    }
  }
  public func capabilities() -> CapabilityDocument {
    CapabilityDocument(
      effectiveVersion: version.description, schemaReviewDate: "2026-08-15",
      operationIDs: MetaAdsCapabilityCatalog.operationIDs)
  }
  private func list<Item: Decodable & Sendable>(
    _ path: String, _ fields: FieldSelection, _ page: PageRequest, filters: [MetaAdsFilter],
    as _: Item.Type
  ) async throws -> GraphPage<Item> {
    var items = [("fields", fields.encoded)]
    if !filters.isEmpty {
      items.append(("filtering", try MetaAdsFilterEncoding.queryValue(filters)))
    }
    items.append(contentsOf: page.queryItems())
    let query = try GraphQuery(items)
    let response = try await reader.get(
      path: GraphPath(relative: path), version: version, query: query)
    let envelope = try JSONDecoder().decode(MetaAdsEnvelope<Item>.self, from: response.data)
    return GraphPage(
      data: envelope.data, after: envelope.paging?.cursors?.after.flatMap { try? PageCursor($0) },
      receivedBytes: response.data.count)
  }
  private func insightList(
    _ path: String, _ fields: FieldSelection, _ page: PageRequest, filters: [MetaAdsFilter]
  ) async throws
    -> GraphPage<InsightRow>
  {
    var items = [("fields", fields.encoded)]
    if !filters.isEmpty {
      items.append(("filtering", try MetaAdsFilterEncoding.queryValue(filters)))
    }
    items.append(contentsOf: page.queryItems())
    let response = try await reader.get(
      path: GraphPath(relative: path), version: version, query: GraphQuery(items))
    let envelope = try JSONDecoder().decode(InsightEnvelope.self, from: response.data)
    return GraphPage(
      data: envelope.data, after: envelope.paging?.cursors?.after.flatMap { try? PageCursor($0) },
      receivedBytes: response.data.count)
  }
  private func one<Item: Decodable>(
    _ path: String, _ fields: FieldSelection, as _: Item.Type
  ) async throws -> Item {
    let response = try await reader.get(
      path: GraphPath(relative: path), version: version,
      query: GraphQuery([("fields", fields.encoded)]))
    return try JSONDecoder().decode(Item.self, from: response.data)
  }
}

public enum MetaAdsCapabilityCatalog {
  public struct Descriptor: Sendable, Equatable {
    public enum Kind: String, Sendable { case list, get, insights }
    public let operationID: String
    public let domain: MetaAdsDomain
    public let kind: Kind
    public let cliSubject: String
    public let requiresAccount: Bool
  }

  public static let descriptors = [
    Descriptor(
      operationID: "meta.ads.ad-accounts.list", domain: .adAccount, kind: .list,
      cliSubject: "adaccounts", requiresAccount: false),
    Descriptor(
      operationID: "meta.ads.ad-accounts.get", domain: .adAccount, kind: .get,
      cliSubject: "adaccount", requiresAccount: false),
    Descriptor(
      operationID: "meta.ads.campaigns.list", domain: .campaign, kind: .list,
      cliSubject: "campaigns", requiresAccount: true),
    Descriptor(
      operationID: "meta.ads.campaigns.get", domain: .campaign, kind: .get,
      cliSubject: "campaign", requiresAccount: false),
    Descriptor(
      operationID: "meta.ads.ad-sets.list", domain: .adSet, kind: .list,
      cliSubject: "adsets", requiresAccount: true),
    Descriptor(
      operationID: "meta.ads.ad-sets.get", domain: .adSet, kind: .get,
      cliSubject: "adset", requiresAccount: false),
    Descriptor(
      operationID: "meta.ads.ads.list", domain: .ad, kind: .list,
      cliSubject: "ads", requiresAccount: true),
    Descriptor(
      operationID: "meta.ads.ads.get", domain: .ad, kind: .get,
      cliSubject: "ad", requiresAccount: false),
    Descriptor(
      operationID: "meta.ads.ad-creatives.list", domain: .adCreative, kind: .list,
      cliSubject: "adcreatives", requiresAccount: true),
    Descriptor(
      operationID: "meta.ads.ad-creatives.get", domain: .adCreative, kind: .get,
      cliSubject: "adcreative", requiresAccount: false),
    Descriptor(
      operationID: "meta.ads.insights.read", domain: .insight, kind: .insights,
      cliSubject: "insights", requiresAccount: false),
  ]

  public static let operationIDs = descriptors.map(\.operationID)

  public static func listDescriptor(for subject: String) -> Descriptor? {
    descriptors.first { $0.kind == .list && $0.cliSubject == subject }
  }
}
private struct MetaAdsEnvelope<Item: Decodable>: Decodable {
  let data: [Item]
  let paging: Paging?
  struct Paging: Decodable {
    let cursors: Cursors?
    struct Cursors: Decodable { let after: String? }
  }
}
private struct InsightEnvelope: Decodable {
  let data: [InsightRow]
  let paging: MetaAdsEnvelope<InsightRow>.Paging?
}
struct AnyCodingKey: CodingKey {
  let stringValue: String
  init(_ value: String) { stringValue = value }
  init?(stringValue: String) { self.stringValue = stringValue }
  let intValue: Int? = nil
  init?(intValue: Int) { nil }
}
