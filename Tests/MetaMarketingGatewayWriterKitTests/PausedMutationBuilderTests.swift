import XCTest

@testable import MetaGraphPrimitives
@testable import MetaMarketingGatewayWriterKit

final class PausedMutationBuilderTests: XCTestCase {
  func testCampaignCreationFixesPausedStatus() throws {
    let request = try PausedMutationBuilders.campaign(
      account: "act_1", name: "safe", objective: "OUTCOME_TRAFFIC",
      version: GraphAPIVersion("v25.0"))
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: String])
    XCTAssertEqual(object["status"], "PAUSED")
    XCTAssertEqual(request.operationID, "meta.ads.campaign.create")
  }

  func testCreativeHasNoServingCarrier() throws {
    let request = try PausedMutationBuilders.creative(
      account: "act_1", name: "safe", objectStorySpec: "{}", version: GraphAPIVersion("v25.0"))
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: String])
    XCTAssertNil(object["status"])
    XCTAssertNil(object["budget"])
  }
}
