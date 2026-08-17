import Foundation
import MetaGraphPrimitives

public struct MetaGraphDeleter: Sendable {
  private let transport: any DeleteGraphTransport
  private let credentials: any DeleteGraphCredentialResolving

  public init(
    transport: any DeleteGraphTransport = URLSessionDeleteGraphTransport(),
    credentials: any DeleteGraphCredentialResolving = KinkoDeleteCredentials()
  ) {
    self.transport = transport
    self.credentials = credentials
  }

  /// The caller must repeat the canonical relative path. This prevents a stale
  /// confirmation for one object from authorizing deletion of another object.
  public func delete(
    version: GraphAPIVersion, path: GraphPath, query: GraphQuery = try! GraphQuery(),
    confirmedPath: String
  ) async throws -> GraphResponse {
    guard confirmedPath == path.description else { throw GraphValidationError.policyDenied }
    let response = try await transport.send(
      DeleteGraphRequest(version: version, path: path, query: query),
      credential: credentials.resolve())
    return response
  }
}
