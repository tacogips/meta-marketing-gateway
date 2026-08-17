import Foundation
import MetaGraphPrimitives

/// Reader-owned request and transport contracts have no mutation verb, body,
/// operation identifier, or arbitrary header capability.  A mutation cannot
/// be represented by this public API.
public struct ReaderGraphRequest: Sendable, Equatable {
  public let version: GraphAPIVersion
  public let path: GraphPath
  public let query: GraphQuery

  public init(
    version: GraphAPIVersion, path: GraphPath, query: GraphQuery = try! GraphQuery()
  ) {
    self.version = version
    self.path = path
    self.query = query
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

public struct ReaderGraphCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible
{
  let token: String
  init(token: String) { self.token = token }
  func applyAuthorization(to request: inout URLRequest) {
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  }
  public var description: String { "<redacted credential>" }
  public var debugDescription: String { description }
}

public protocol ReaderGraphCredentialResolving: Sendable {
  func resolve() throws -> ReaderGraphCredential
}

public struct ReaderKinkoEnvironmentCredentials: ReaderGraphCredentialResolving {
  public init() {}
  public func resolve() throws -> ReaderGraphCredential {
    guard let token = ProcessInfo.processInfo.environment["META_ACCESS_TOKEN"],
      !token.isEmpty, token.utf8.count <= 16_384
    else { throw GraphValidationError.missingCredential }
    return ReaderGraphCredential(token: token)
  }
}

public protocol ReaderGraphTransport: Sendable {
  func send(_ request: ReaderGraphRequest, credential: ReaderGraphCredential) async throws
    -> GraphResponse
}
