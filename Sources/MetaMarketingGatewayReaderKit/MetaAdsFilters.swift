import Foundation
import MetaGraphPrimitives

public enum MetaAdsFilterOperator: String, Sendable, Codable, CaseIterable {
  case equal = "EQUAL"
  case notEqual = "NOT_EQUAL"
  case greaterThan = "GREATER_THAN"
  case lessThan = "LESS_THAN"
  case `in` = "IN"
  case notIn = "NOT_IN"
}

public enum MetaAdsFilterValue: Sendable, Equatable, Codable {
  case string(String)
  case integer(Int64)
  case boolean(Bool)
  case strings([String])
  case integers([Int64])

  public func encode(to encoder: Encoder) throws {
    try validate()
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .boolean(let value): try container.encode(value)
    case .strings(let values):
      try container.encode(values)
    case .integers(let values):
      try container.encode(values)
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .integer(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let values = try? container.decode([Int64].self) {
      self = .integers(values)
    } else if let values = try? container.decode([String].self) {
      self = .strings(values)
    } else {
      throw GraphValidationError.invalidRequest
    }
    try validate()
  }

  fileprivate func validate() throws {
    switch self {
    case .string(let value):
      guard !value.isEmpty, value.utf8.count <= 4_096,
        value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
      else { throw GraphValidationError.invalidRequest }
    case .strings(let values):
      guard !values.isEmpty, values.count <= 64,
        values.allSatisfy({
          !$0.isEmpty && $0.utf8.count <= 4_096
            && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        })
      else { throw GraphValidationError.invalidRequest }
    case .integers(let values):
      guard !values.isEmpty, values.count <= 64 else { throw GraphValidationError.invalidRequest }
    case .integer, .boolean: break
    }
  }
}

public struct MetaAdsFilter: Sendable, Equatable, Codable {
  public let field: String
  public let operation: MetaAdsFilterOperator
  public let value: MetaAdsFilterValue

  public init(field: String, operation: MetaAdsFilterOperator, value: MetaAdsFilterValue) throws {
    guard field.wholeMatch(of: /[a-z][a-z0-9_]*/) != nil else {
      throw GraphValidationError.invalidRequest
    }
    try value.validate()
    self.field = field
    self.operation = operation
    self.value = value
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      field: c.decode(String.self, forKey: .field),
      operation: c.decode(MetaAdsFilterOperator.self, forKey: .operation),
      value: c.decode(MetaAdsFilterValue.self, forKey: .value))
  }
  private enum CodingKeys: String, CodingKey { case field, operation, value }
}

public enum MetaAdsFilterEncoding {
  public static func queryValue(_ filters: [MetaAdsFilter]) throws -> String {
    guard filters.count <= 50 else { throw GraphValidationError.invalidRequest }
    let data = try JSONEncoder().encode(filters.map(FilterWire.init))
    guard data.count <= 65_536, let encoded = String(data: data, encoding: .utf8) else {
      throw GraphValidationError.invalidRequest
    }
    return encoded
  }
  public static func loadFile(_ url: URL) throws -> [MetaAdsFilter] {
    let filters = try SecureFile.read([MetaAdsFilter].self, from: url)
    _ = try queryValue(filters)
    return filters
  }
}

private struct FilterWire: Encodable {
  let filter: MetaAdsFilter
  init(_ filter: MetaAdsFilter) { self.filter = filter }
  enum CodingKeys: String, CodingKey { case field, `operator`, value }
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(filter.field, forKey: .field)
    try container.encode(filter.operation.rawValue, forKey: .operator)
    try filter.value.encode(to: container.superEncoder(forKey: .value))
  }
}
