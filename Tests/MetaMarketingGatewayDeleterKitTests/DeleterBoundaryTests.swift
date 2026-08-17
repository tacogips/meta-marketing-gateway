import XCTest

@testable import MetaGraphPrimitives
@testable import MetaMarketingGatewayDeleterKit

final class DeleterBoundaryTests: XCTestCase {
  func testDeleteRequestUsesFixedOriginAndCarriesNoBodyOrMethodChoice() throws {
    let request = DeleteGraphRequest(
      version: try GraphAPIVersion("v25.0"), path: try GraphPath(relative: "123456"))
    XCTAssertEqual(try request.url().absoluteString, "https://graph.facebook.com/v25.0/123456")
  }

  func testExactPathConfirmationIsRequiredBeforeTransport() async throws {
    let transport = RecordingDeleteTransport()
    let deleter = MetaGraphDeleter(transport: transport, credentials: TestDeleteCredentials())
    let version = try GraphAPIVersion("v25.0")
    let path = try GraphPath(relative: "123456")

    do {
      _ = try await deleter.delete(version: version, path: path, confirmedPath: "654321")
      XCTFail("mismatched confirmation must fail")
    } catch {}
    let deniedCalls = await transport.callCount
    XCTAssertEqual(deniedCalls, 0)

    let response = try await deleter.delete(
      version: version, path: path, confirmedPath: path.description)
    XCTAssertEqual(response.status, 200)
    let acceptedCalls = await transport.callCount
    XCTAssertEqual(acceptedCalls, 1)
  }

  func testCatalogContainsTypedAndGenericDeleteCoverage() {
    XCTAssertTrue(DeleterCapabilityCatalog.operations.contains("meta.ads.campaign.delete"))
    XCTAssertTrue(DeleterCapabilityCatalog.operations.contains("meta.ads.adset.delete"))
    XCTAssertTrue(DeleterCapabilityCatalog.operations.contains("meta.ads.ad.delete"))
    XCTAssertTrue(DeleterCapabilityCatalog.operations.contains("meta.ads.adcreative.delete"))
    XCTAssertTrue(DeleterCapabilityCatalog.operations.contains("meta.generic.delete"))
  }
}

private struct TestDeleteCredentials: DeleteGraphCredentialResolving {
  func resolve() throws -> DeleteGraphCredential { DeleteGraphCredential(token: "test-sentinel") }
}

private actor RecordingDeleteTransport: DeleteGraphTransport {
  private(set) var callCount = 0
  func send(_ request: DeleteGraphRequest, credential: DeleteGraphCredential) async throws
    -> GraphResponse
  {
    callCount += 1
    return try GraphResponse(status: 200, data: Data(#"{"success":true}"#.utf8))
  }
}
