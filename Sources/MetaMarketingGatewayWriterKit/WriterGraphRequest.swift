import Foundation
import MetaGraphPrimitives

/// Writer-only request material.  This target owns mutation verbs, bodies,
/// operation identifiers, credentials, and executable transport authority.
/// The Reader and primitives products cannot link these symbols.
public enum GraphMethod: String, Sendable, Codable {
  case post = "POST"
}

public enum GraphBodyMediaType: String, Sendable, Codable { case json = "application/json" }

public struct GraphRequest: Sendable, Equatable {
  public let method: GraphMethod
  public let version: GraphAPIVersion
  public let path: GraphPath
  public let query: GraphQuery
  public let body: Data?
  public let bodyMediaType: GraphBodyMediaType?
  public let operationID: String?

  public init(
    method: GraphMethod, version: GraphAPIVersion, path: GraphPath,
    query: GraphQuery = try! GraphQuery(), body: Data? = nil,
    bodyMediaType: GraphBodyMediaType? = nil, operationID: String? = nil
  ) throws {
    let resolvedOperationID = operationID ?? "meta.generic.write"
    guard body?.count ?? 0 <= 1_048_576,
      (body == nil) == (bodyMediaType == nil),
      resolvedOperationID.wholeMatch(of: /meta\.[a-z0-9.-]{3,127}/) != nil
    else { throw GraphValidationError.invalidRequest }
    self.method = method
    self.version = version
    self.path = path
    self.query = query
    self.body = body
    self.bodyMediaType = bodyMediaType
    self.operationID = resolvedOperationID
  }

  public func url() throws -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "graph.facebook.com"
    components.path = "/\(version.description)/\(path.description)"
    let encoded = query.encoded()
    components.percentEncodedQuery = encoded.isEmpty ? nil : encoded
    guard let url = components.url, url.host == "graph.facebook.com", url.scheme == "https" else {
      throw GraphValidationError.invalidRequest
    }
    return url
  }
}

public protocol GraphTransport: Sendable {
  func send(_ request: GraphRequest, credential: GraphCredential) async throws -> GraphResponse
}

public struct GraphCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  let token: String
  init(token: String) { self.token = token }
  public func applyAuthorization(to request: inout URLRequest) {
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  }
  public var description: String { "<redacted credential>" }
  public var debugDescription: String { description }
}

public protocol GraphCredentialResolving: Sendable { func resolve() throws -> GraphCredential }

/// This adapter accepts only the explicit environment name supplied by
/// `kinko exec --env META_ACCESS_TOKEN -- …`; no file, argument, stdin, or
/// arbitrary environment lookup is implemented.
public struct KinkoEnvironmentCredentials: GraphCredentialResolving {
  public init() {}
  public func resolve() throws -> GraphCredential {
    guard let token = ProcessInfo.processInfo.environment["META_ACCESS_TOKEN"],
      !token.isEmpty, token.utf8.count <= 16_384
    else { throw GraphValidationError.missingCredential }
    return GraphCredential(token: token)
  }
}
