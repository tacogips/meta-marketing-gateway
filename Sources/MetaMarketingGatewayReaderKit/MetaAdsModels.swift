import Foundation

/// Provider enums evolve independently of a client release. Known values are
/// convenient to compare while every unrecognised value remains observable and
/// lossless instead of becoming a decoding failure.
public enum TolerantProviderEnum: Sendable, Codable, Equatable {
  case known(String)
  case unknown(String)

  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    switch value {
    case "ACTIVE", "PAUSED", "ARCHIVED", "DELETED", "DISABLED", "IN_PROCESS":
      self = .known(value)
    default:
      self = .unknown(value)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .known(let value), .unknown(let value): try container.encode(value)
    }
  }
}

/// The common envelope preserves unknown fields in their original JSON shape.
/// Domain models below deliberately expose nominal types even where Meta's
/// conservative v26 field sets overlap, preventing accidental cross-domain ID
/// or status assumptions at call sites.
public struct TolerantAdsRecord: Sendable, Codable, Equatable {
  public let id: String?
  public let accountID: String?
  public let campaignID: String?
  public let adSetID: String?
  public let name: String?
  public let status: TolerantProviderEnum?
  public let effectiveStatus: TolerantProviderEnum?
  public let additionalFields: [String: JSONValue]

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AnyCodingKey.self)
    id = try container.decodeIfPresent(String.self, forKey: .init("id"))
    accountID = try container.decodeIfPresent(String.self, forKey: .init("account_id"))
    campaignID = try container.decodeIfPresent(String.self, forKey: .init("campaign_id"))
    adSetID = try container.decodeIfPresent(String.self, forKey: .init("adset_id"))
    name = try container.decodeIfPresent(String.self, forKey: .init("name"))
    status = try container.decodeIfPresent(TolerantProviderEnum.self, forKey: .init("status"))
    effectiveStatus = try container.decodeIfPresent(
      TolerantProviderEnum.self, forKey: .init("effective_status"))
    let known: Set<String> = [
      "id", "account_id", "campaign_id", "adset_id", "name", "status", "effective_status",
    ]
    additionalFields = try Dictionary(
      uniqueKeysWithValues: container.allKeys.filter { !known.contains($0.stringValue) }.map {
        ($0.stringValue, try container.decode(JSONValue.self, forKey: $0))
      })
  }
}

public struct AdAccount: Sendable, Codable, Equatable {
  public let record: TolerantAdsRecord
  public init(from decoder: Decoder) throws { record = try TolerantAdsRecord(from: decoder) }
  public var id: String? { record.id }
  public var accountID: String? { record.accountID }
  public var name: String? { record.name }
  public var accountStatus: JSONValue? { record.additionalFields["account_status"] }
  public var currency: String? { record.additionalFields["currency"]?.stringValue }
  public var timezoneName: String? { record.additionalFields["timezone_name"]?.stringValue }
  public var businessName: String? { record.additionalFields["business_name"]?.stringValue }
  public var createdTime: String? { record.additionalFields["created_time"]?.stringValue }
  public var additionalFields: [String: JSONValue] {
    record.additionalFields.removing(keys: [
      "account_status", "currency", "timezone_name", "business_name", "created_time",
    ])
  }
}
public struct Campaign: Sendable, Codable, Equatable {
  public let record: TolerantAdsRecord
  public init(from decoder: Decoder) throws { record = try TolerantAdsRecord(from: decoder) }
  public var id: String? { record.id }
  public var accountID: String? { record.accountID }
  public var name: String? { record.name }
  public var objective: String? { record.additionalFields["objective"]?.stringValue }
  public var status: TolerantProviderEnum? { record.status }
  public var effectiveStatus: TolerantProviderEnum? { record.effectiveStatus }
  public var buyingType: String? { record.additionalFields["buying_type"]?.stringValue }
  public var startTime: String? { record.additionalFields["start_time"]?.stringValue }
  public var stopTime: String? { record.additionalFields["stop_time"]?.stringValue }
  public var createdTime: String? { record.additionalFields["created_time"]?.stringValue }
  public var updatedTime: String? { record.additionalFields["updated_time"]?.stringValue }
  public var additionalFields: [String: JSONValue] {
    record.additionalFields.removing(keys: [
      "objective", "buying_type", "start_time", "stop_time", "created_time", "updated_time",
    ])
  }
}
public struct AdSet: Sendable, Codable, Equatable {
  public let record: TolerantAdsRecord
  public init(from decoder: Decoder) throws { record = try TolerantAdsRecord(from: decoder) }
  public var id: String? { record.id }
  public var accountID: String? { record.accountID }
  public var campaignID: String? { record.campaignID }
  public var name: String? { record.name }
  public var status: TolerantProviderEnum? { record.status }
  public var effectiveStatus: TolerantProviderEnum? { record.effectiveStatus }
  public var optimizationGoal: String? { record.additionalFields["optimization_goal"]?.stringValue }
  public var billingEvent: String? { record.additionalFields["billing_event"]?.stringValue }
  public var startTime: String? { record.additionalFields["start_time"]?.stringValue }
  public var endTime: String? { record.additionalFields["end_time"]?.stringValue }
  public var createdTime: String? { record.additionalFields["created_time"]?.stringValue }
  public var updatedTime: String? { record.additionalFields["updated_time"]?.stringValue }
  public var additionalFields: [String: JSONValue] {
    record.additionalFields.removing(keys: [
      "optimization_goal", "billing_event", "start_time", "end_time", "created_time",
      "updated_time",
    ])
  }
}
public struct Ad: Sendable, Codable, Equatable {
  public let record: TolerantAdsRecord
  public init(from decoder: Decoder) throws { record = try TolerantAdsRecord(from: decoder) }
  public var id: String? { record.id }
  public var accountID: String? { record.accountID }
  public var campaignID: String? { record.campaignID }
  public var adSetID: String? { record.adSetID }
  public var name: String? { record.name }
  public var status: TolerantProviderEnum? { record.status }
  public var effectiveStatus: TolerantProviderEnum? { record.effectiveStatus }
  public var creative: JSONValue? { record.additionalFields["creative"] }
  public var createdTime: String? { record.additionalFields["created_time"]?.stringValue }
  public var updatedTime: String? { record.additionalFields["updated_time"]?.stringValue }
  public var additionalFields: [String: JSONValue] {
    record.additionalFields.removing(keys: ["creative", "created_time", "updated_time"])
  }
}
public struct AdCreative: Sendable, Codable, Equatable {
  public let record: TolerantAdsRecord
  public init(from decoder: Decoder) throws { record = try TolerantAdsRecord(from: decoder) }
  public var id: String? { record.id }
  public var accountID: String? { record.accountID }
  public var name: String? { record.name }
  public var title: String? { record.additionalFields["title"]?.stringValue }
  public var body: String? { record.additionalFields["body"]?.stringValue }
  public var status: TolerantProviderEnum? { record.status }
  public var thumbnailURL: String? { record.additionalFields["thumbnail_url"]?.stringValue }
  public var objectStoryID: String? { record.additionalFields["object_story_id"]?.stringValue }
  public var createdTime: String? { record.additionalFields["created_time"]?.stringValue }
  public var additionalFields: [String: JSONValue] {
    record.additionalFields.removing(keys: [
      "title", "body", "thumbnail_url", "object_story_id", "created_time",
    ])
  }
}

extension JSONValue {
  fileprivate var stringValue: String? {
    guard case .string(let value) = storage else { return nil }
    return value
  }
}

extension Dictionary where Key == String, Value == JSONValue {
  fileprivate func removing(keys: Set<String>) -> Self { filter { !keys.contains($0.key) } }
  fileprivate func removing(keys: [String]) -> Self { removing(keys: Set(keys)) }
}
