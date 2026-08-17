import Foundation

public struct GraphAPIVersion: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
  public let major: Int
  public let minor: Int

  public init(_ value: String) throws {
    guard value.utf8.count <= 16,
      let match = value.wholeMatch(of: /v([0-9]+)\.([0-9]+)/),
      let major = Int(match.1), let minor = Int(match.2), major > 0,
      major <= 999, minor <= 999
    else {
      throw GraphValidationError.invalidAPIVersion
    }
    self.major = major
    self.minor = minor
  }

  public var description: String { "v\(major).\(minor)" }
}

public enum GraphValidationError: Error, Sendable, Equatable, LocalizedError {
  case invalidAPIVersion
  case invalidPath
  case invalidQuery
  case invalidIdentifier
  case invalidPagination
  case invalidRequest
  case policyDenied
  case planMismatch
  case planExpired
  case missingCredential

  public var errorDescription: String? {
    switch self {
    case .invalidAPIVersion: "invalid API version"
    case .invalidPath: "invalid relative Graph path"
    case .invalidQuery: "invalid query parameter"
    case .invalidIdentifier: "invalid identifier"
    case .invalidPagination: "invalid pagination cursor"
    case .invalidRequest: "invalid request"
    case .policyDenied: "operation denied by safety policy"
    case .planMismatch: "plan does not match request or confirmation"
    case .planExpired: "plan has expired"
    case .missingCredential: "required credential is unavailable"
    }
  }
}
