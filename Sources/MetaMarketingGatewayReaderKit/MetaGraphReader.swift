import Foundation
import MetaGraphPrimitives

public protocol MetaGraphReading: Sendable {
  func get(path: GraphPath, version: GraphAPIVersion, query: GraphQuery) async throws
    -> GraphResponse
}

public struct MetaGraphReader: MetaGraphReading {
  private let transport: any ReaderGraphTransport
  private let credentials: any ReaderGraphCredentialResolving
  public init(
    transport: any ReaderGraphTransport,
    credentials: any ReaderGraphCredentialResolving = ReaderKinkoEnvironmentCredentials()
  ) {
    self.transport = transport
    self.credentials = credentials
  }
  public func get(path: GraphPath, version: GraphAPIVersion, query: GraphQuery = try! GraphQuery())
    async throws -> GraphResponse
  {
    let request = ReaderGraphRequest(version: version, path: path, query: query)
    return try await GraphReadExecutor(transport: transport).send(
      request, credential: credentials.resolve())
  }

  public func get(batch: GraphReadBatch) async throws -> [GraphBatchResult] {
    guard let batchTransport = transport as? any GraphReadBatchExecuting else {
      throw GraphValidationError.policyDenied
    }
    return try await batchTransport.send(batch: batch, credential: credentials.resolve())
  }
}

public struct PageCursor: Sendable, Equatable, Codable {
  public let value: String
  public init(_ value: String) throws {
    guard !value.isEmpty, value.utf8.count <= 16_384,
      value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else { throw GraphValidationError.invalidPagination }
    self.value = value
  }
}

public enum CursorDirection: Sendable, Equatable {
  case after(PageCursor)
  case before(PageCursor)
}
public struct PageRequest: Sendable, Equatable {
  public let limit: Int?
  public let direction: CursorDirection?
  public init(limit: Int? = nil, direction: CursorDirection? = nil) throws {
    guard limit == nil || (1...500).contains(limit!) else {
      throw GraphValidationError.invalidPagination
    }
    self.limit = limit
    self.direction = direction
  }
  public func queryItems() -> [(String, String)] {
    var result: [(String, String)] = []
    if let limit { result.append(("limit", String(limit))) }
    if case .after(let cursor) = direction { result.append(("after", cursor.value)) }
    if case .before(let cursor) = direction { result.append(("before", cursor.value)) }
    return result
  }
}

public enum GraphPagination {
  public static func cursor(from nextURL: String, version: GraphAPIVersion) throws -> PageCursor? {
    guard let components = URLComponents(string: nextURL), components.scheme == "https",
      components.host == "graph.facebook.com",
      components.port == nil, components.user == nil, components.password == nil,
      components.fragment == nil,
      components.path.hasPrefix("/\(version.description)/")
    else { throw GraphValidationError.invalidPagination }
    let values = components.queryItems?.filter { $0.name == "after" || $0.name == "before" } ?? []
    guard values.count <= 1 else { throw GraphValidationError.invalidPagination }
    return try values.first.flatMap { try $0.value.map(PageCursor.init) }
  }
}
