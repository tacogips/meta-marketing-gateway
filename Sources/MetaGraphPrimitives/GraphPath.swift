import Foundation

public struct GraphPath: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
  public let segments: [String]

  public init(segments: [String]) throws {
    guard !segments.isEmpty, segments.allSatisfy(Self.isSafeSegment) else {
      throw GraphValidationError.invalidPath
    }
    self.segments = segments
  }

  public init(relative value: String) throws {
    guard !value.isEmpty, value.utf8.count <= 4096,
      !value.hasPrefix("//"), !value.contains("://"), !value.contains("?"),
      !value.contains("#"), !value.contains("\\")
    else { throw GraphValidationError.invalidPath }
    let stripped = value.hasPrefix("/") ? String(value.dropFirst()) : value
    try self.init(
      segments: stripped.split(separator: "/", omittingEmptySubsequences: false).map(String.init))
  }

  public var description: String { segments.joined(separator: "/") }

  private static func isSafeSegment(_ value: String) -> Bool {
    guard !value.isEmpty, value != ".", value != "..", value.utf8.count <= 512,
      !value.contains("%"), !value.contains("\\")
    else { return false }
    return value.unicodeScalars.allSatisfy { scalar in
      !CharacterSet.controlCharacters.contains(scalar) && scalar != "/" && scalar != "?"
        && scalar != "#"
    }
  }
}

public struct GraphQuery: Sendable, Equatable {
  public let items: [(String, String)]

  public init(_ items: [(String, String)] = []) throws {
    let reserved = Set(["access_token", "appsecret_proof", "authorization", "cookie"])
    guard items.count <= 100,
      items.allSatisfy({ key, value in
        !key.isEmpty && key.utf8.count <= 128 && value.utf8.count <= 16_384
          && key.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
          && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
          && !reserved.contains(key.lowercased())
      })
    else { throw GraphValidationError.invalidQuery }
    self.items = items
  }

  public func encoded() -> String {
    items.map { "\(Self.escape($0.0))=\(Self.escape($0.1))" }.joined(separator: "&")
  }

  public static func == (lhs: GraphQuery, rhs: GraphQuery) -> Bool {
    lhs.items.elementsEqual(rhs.items, by: { $0.0 == $1.0 && $0.1 == $1.1 })
  }

  private static func escape(_ value: String) -> String {
    value.addingPercentEncoding(
      withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
  }
}
