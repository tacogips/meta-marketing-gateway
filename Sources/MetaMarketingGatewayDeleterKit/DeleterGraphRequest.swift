import Foundation
import MetaGraphPrimitives

/// A request whose HTTP method is structurally fixed to DELETE. Reader and
/// Writer targets cannot import or construct this type.
public struct DeleteGraphRequest: Sendable, Equatable {
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
    guard let url = components.url, url.scheme == "https", url.host == "graph.facebook.com" else {
      throw GraphValidationError.invalidRequest
    }
    return url
  }
}

public struct DeleteGraphCredential: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  let token: String
  init(token: String) { self.token = token }
  func authorize(_ request: inout URLRequest) {
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  }
  public var description: String { "<redacted credential>" }
  public var debugDescription: String { description }
}

public protocol DeleteGraphCredentialResolving: Sendable {
  func resolve() throws -> DeleteGraphCredential
}

public struct KinkoDeleteCredentials: DeleteGraphCredentialResolving {
  public init() {}
  public func resolve() throws -> DeleteGraphCredential {
    guard let token = ProcessInfo.processInfo.environment["META_ACCESS_TOKEN"],
      !token.isEmpty, token.utf8.count <= 16_384
    else { throw GraphValidationError.missingCredential }
    return DeleteGraphCredential(token: token)
  }
}

public protocol DeleteGraphTransport: Sendable {
  func send(_ request: DeleteGraphRequest, credential: DeleteGraphCredential) async throws
    -> GraphResponse
}
