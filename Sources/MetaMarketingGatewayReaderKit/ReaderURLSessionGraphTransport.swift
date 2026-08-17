import Foundation
import MetaGraphPrimitives

/// Reader-owned transport permits only a canonical GET request. The Graph
/// batch POST envelope is intentionally not exposed by this transport.
public struct ReaderURLSessionGraphTransport: ReaderGraphTransport {
  private let configuration: URLSessionConfiguration

  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    self.configuration = configuration
  }

  public func send(_ request: ReaderGraphRequest, credential: ReaderGraphCredential) async throws
    -> GraphResponse
  {
    var outgoing = URLRequest(url: try request.url())
    outgoing.httpMethod = "GET"
    outgoing.timeoutInterval = 30
    credential.applyAuthorization(to: &outgoing)
    let session = URLSession(
      configuration: configuration, delegate: ReaderRejectingRedirectDelegate(), delegateQueue: nil)
    let (bytes, response) = try await session.bytes(for: outgoing)
    guard let http = response as? HTTPURLResponse else { throw GraphValidationError.invalidRequest }
    var data = Data()
    for try await byte in bytes {
      guard data.count < 4_194_304 else { throw GraphValidationError.invalidRequest }
      data.append(byte)
    }
    return try GraphResponse(status: http.statusCode, data: data)
  }
}

private final class ReaderRejectingRedirectDelegate: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard request.url?.scheme == "https", request.url?.host == "graph.facebook.com" else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    completionHandler(.performDefaultHandling, nil)
  }

}
