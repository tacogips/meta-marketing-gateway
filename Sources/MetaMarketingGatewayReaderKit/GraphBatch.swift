import Foundation
import MetaGraphPrimitives

public struct GraphBatchItem: Sendable, Equatable {
  public let name: String
  public let request: ReaderGraphRequest
  public let dependsOn: [String]
  public let omitResponseOnSuccess: Bool

  public init(
    name: String, request: ReaderGraphRequest, dependsOn: [String] = [],
    omitResponseOnSuccess: Bool = false
  ) throws {
    // Meta's documented `depends_on` field is a single named predecessor. Do
    // not invent comma-list semantics that a provider could interpret differently.
    guard Self.validName(name), dependsOn.count <= 1, dependsOn.allSatisfy(Self.validName),
      !dependsOn.contains(name), Set(dependsOn).count == dependsOn.count
    else { throw GraphValidationError.invalidRequest }
    self.name = name
    self.request = request
    self.dependsOn = dependsOn
    self.omitResponseOnSuccess = omitResponseOnSuccess
  }
  private static func validName(_ value: String) -> Bool {
    value.wholeMatch(of: /[A-Za-z][A-Za-z0-9_-]{0,63}/) != nil
  }
}

public struct GraphReadBatch: Sendable, Equatable {
  public let items: [GraphBatchItem]
  public let version: GraphAPIVersion

  public init(items: [GraphBatchItem]) throws {
    guard !items.isEmpty, items.count <= 50, Set(items.map(\.name)).count == items.count,
      true
    else { throw GraphValidationError.policyDenied }
    let names = Set(items.map(\.name))
    guard items.allSatisfy({ Set($0.dependsOn).isSubset(of: names) }), !Self.hasCycle(items) else {
      throw GraphValidationError.invalidRequest
    }
    guard let version = items.first?.request.version,
      items.allSatisfy({ $0.request.version == version })
    else { throw GraphValidationError.invalidRequest }
    self.items = items
    self.version = version
  }

  private static func hasCycle(_ items: [GraphBatchItem]) -> Bool {
    let dependencies = Dictionary(uniqueKeysWithValues: items.map { ($0.name, Set($0.dependsOn)) })
    var active = Set<String>()
    var complete = Set<String>()
    func visit(_ name: String) -> Bool {
      if complete.contains(name) { return false }
      if !active.insert(name).inserted { return true }
      let cyclic = dependencies[name, default: []].contains { visit($0) }
      active.remove(name)
      complete.insert(name)
      return cyclic
    }
    return items.contains { visit($0.name) }
  }

  /// Meta's batch endpoint accepts a JSON value in a form field. Every relative URL
  /// below is reconstructed from validated request components; auth never enters it.
  public func formBody() throws -> Data {
    let encoded = try JSONEncoder().encode(items.map(BatchWire.init))
    guard encoded.count <= 1_048_576 else { throw GraphValidationError.invalidRequest }
    let batch = String(decoding: encoded, as: UTF8.self)
    return Data("batch=\(GraphBatchForm.escape(batch))".utf8)
  }
}

/// A reader-only capability. Its POST is an implementation detail of the
/// provider's batch envelope; every represented subrequest remains a GET.
public protocol GraphReadBatchExecuting: Sendable {
  func send(batch: GraphReadBatch, credential: ReaderGraphCredential) async throws
    -> [GraphBatchResult]
}

public struct GraphBatchResult: Sendable, Equatable {
  public let status: Int
  public let body: Data?
  public let omitted: Bool
  public let headers: [String: String]
  public let providerError: GraphBatchProviderError?

  public init(
    status: Int, body: Data?, omitted: Bool, headers: [String: String] = [:],
    providerError: GraphBatchProviderError? = nil
  ) {
    self.status = status
    self.body = body
    self.omitted = omitted
    self.headers = headers
    self.providerError = providerError
  }
}

public struct GraphBatchProviderError: Sendable, Equatable {
  public let code: Int?
  public let subcode: Int?
  public let isTransient: Bool?
}

public enum GraphBatchResponse {
  public static func decode(_ data: Data, expectedCount: Int) throws -> [GraphBatchResult] {
    guard data.count <= 4_194_304 else { throw GraphValidationError.invalidRequest }
    let wires = try JSONDecoder().decode([ResponseWire].self, from: data)
    guard wires.count == expectedCount else { throw GraphValidationError.invalidRequest }
    return try wires.map { wire in
      guard (100...599).contains(wire.code), (wire.body?.utf8.count ?? 0) <= 1_048_576,
        wire.headers.count <= 32
      else {
        throw GraphValidationError.invalidRequest
      }
      guard wire.body != nil || (200...299).contains(wire.code) else {
        throw GraphValidationError.invalidRequest
      }
      let headers = try safeHeaders(wire.headers)
      return GraphBatchResult(
        status: wire.code, body: wire.body.map { Data($0.utf8) }, omitted: wire.body == nil,
        headers: headers, providerError: safeError(from: wire.body))
    }
  }

  private static func safeHeaders(_ headers: [HeaderWire]) throws -> [String: String] {
    let allowed = Set(["content-type", "etag", "x-fb-trace-id"])
    var safe: [String: String] = [:]
    for header in headers {
      let name = header.name.lowercased()
      guard header.name.utf8.count <= 64, header.value.utf8.count <= 256,
        header.name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
        header.value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
      else { throw GraphValidationError.invalidRequest }
      if allowed.contains(name) { safe[name] = header.value }
    }
    return safe
  }

  private static func safeError(from body: String?) -> GraphBatchProviderError? {
    guard let body, body.utf8.count <= 1_048_576,
      let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
      let error = object["error"] as? [String: Any]
    else { return nil }
    let code = error["code"] as? Int
    let subcode = error["error_subcode"] as? Int
    let transient = error["is_transient"] as? Bool
    return GraphBatchProviderError(code: code, subcode: subcode, isTransient: transient)
  }
}

private struct BatchWire: Encodable {
  let item: GraphBatchItem
  init(_ item: GraphBatchItem) { self.item = item }
  enum CodingKeys: String, CodingKey {
    case name, method
    case relativeURL = "relative_url"
    case dependsOn = "depends_on"
    case omit = "omit_response_on_success"
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(item.name, forKey: .name)
    try c.encode("GET", forKey: .method)
    let query = item.request.query.encoded()
    try c.encode(
      item.request.path.description + (query.isEmpty ? "" : "?\(query)"), forKey: .relativeURL)
    if !item.dependsOn.isEmpty {
      try c.encode(item.dependsOn.joined(separator: ","), forKey: .dependsOn)
    }
    if item.omitResponseOnSuccess { try c.encode(true, forKey: .omit) }
  }
}

private enum GraphBatchForm {
  static func escape(_ value: String) -> String {
    value.addingPercentEncoding(
      withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
  }
}

private struct ResponseWire: Decodable {
  let code: Int
  let body: String?
  let headers: [HeaderWire]
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    code = try container.decode(Int.self, forKey: .code)
    body = try container.decodeIfPresent(String.self, forKey: .body)
    headers = try container.decodeIfPresent([HeaderWire].self, forKey: .headers) ?? []
  }
  private enum CodingKeys: String, CodingKey { case code, body, headers }
}

private struct HeaderWire: Decodable {
  let name: String
  let value: String
}
