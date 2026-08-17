import Foundation

/// The broker protocol intentionally carries only an opaque record identity
/// and a monotonic digest head. It has no Graph, credential, or journal-event
/// representation, so the broker cannot become a mutation endpoint.
public struct TrustedHead: Codable, Sendable, Equatable {
  public let sequence: UInt64
  public let digest: String

  public init(sequence: UInt64, digest: String) throws {
    guard sequence > 0, digest.wholeMatch(of: /[0-9a-f]{64}/) != nil else {
      throw TrustedHeadProtocolError.invalidMessage
    }
    self.sequence = sequence
    self.digest = digest
  }
}

/// Versioned bounded wire envelopes. They intentionally contain neither a
/// journal event nor provider request material, allowing the broker to anchor
/// only an opaque monotonic digest.
public struct TrustedHeadWireRequest: Codable, Sendable, Equatable {
  public static let schema = 1
  public let schema: Int
  public let operation: String
  public let namespace: String
  public let recordIdentity: String
  public let expected: TrustedHead?
  public let proposed: TrustedHead?

  public init(
    operation: String, namespace: String, recordIdentity: String,
    expected: TrustedHead? = nil, proposed: TrustedHead? = nil
  ) throws {
    guard operation == "readHead" || operation == "compareAndSetHead",
      Self.isValidNamespace(namespace), Self.isDigest(recordIdentity),
      (operation == "readHead" && expected == nil && proposed == nil)
        || (operation == "compareAndSetHead" && proposed != nil)
    else { throw TrustedHeadProtocolError.invalidMessage }
    self.schema = Self.schema
    self.operation = operation
    self.namespace = namespace
    self.recordIdentity = recordIdentity
    self.expected = expected
    self.proposed = proposed
  }

  public func validated() throws -> Self {
    guard schema == Self.schema else { throw TrustedHeadProtocolError.invalidMessage }
    return try Self(
      operation: operation, namespace: namespace, recordIdentity: recordIdentity,
      expected: expected, proposed: proposed)
  }

  public static func isValidNamespace(_ value: String) -> Bool {
    value.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9._-]{0,127}/) != nil
  }

  public static func isDigest(_ value: String) -> Bool {
    value.wholeMatch(of: /[0-9a-f]{64}/) != nil
  }
}

public struct TrustedHeadWireResponse: Codable, Sendable, Equatable {
  public static let schema = 1
  public let schema: Int
  public let head: TrustedHead?
  public let didCompareAndSet: Bool?

  public init(head: TrustedHead) {
    schema = Self.schema
    self.head = head
    didCompareAndSet = nil
  }

  public init(emptyHead: Bool = true) {
    schema = Self.schema
    head = nil
    didCompareAndSet = nil
  }

  public init(didCompareAndSet: Bool) {
    schema = Self.schema
    head = nil
    self.didCompareAndSet = didCompareAndSet
  }
}

public enum TrustedHeadRequest: Codable, Sendable, Equatable {
  case readHead(namespace: String, recordIdentity: String)
  case compareAndSetHead(
    namespace: String, recordIdentity: String, expected: TrustedHead?, proposed: TrustedHead)
}

public enum TrustedHeadResponse: Codable, Sendable, Equatable {
  case head(TrustedHead?)
  case compareAndSet(Bool)
}

public enum TrustedHeadProtocolError: Error, Sendable {
  case invalidMessage
  case denied
}

public protocol TrustedHeadClient: Sendable {
  func readHead(namespace: String, recordIdentity: String) async throws -> TrustedHead?
  func compareAndSetHead(
    namespace: String, recordIdentity: String, expected: TrustedHead?, proposed: TrustedHead
  ) async throws -> Bool
}
