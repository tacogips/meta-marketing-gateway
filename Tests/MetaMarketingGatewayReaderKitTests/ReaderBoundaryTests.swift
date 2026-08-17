import XCTest

@testable import MetaGraphPrimitives
@testable import MetaMarketingGatewayReaderKit

final class ReaderBoundaryTests: XCTestCase {
  func testReaderRequestCannotCarryMutationMaterial() throws {
    let request = ReaderGraphRequest(
      version: try GraphAPIVersion("v25.0"), path: try GraphPath(relative: "act_1/campaigns"))
    XCTAssertEqual(try request.url().path, "/v25.0/act_1/campaigns")
  }
}
