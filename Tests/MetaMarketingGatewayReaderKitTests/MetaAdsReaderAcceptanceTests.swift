import XCTest

@testable import MetaMarketingGatewayReaderKit

final class MetaAdsReaderAcceptanceTests: XCTestCase {
  func testTypedDomainFixtureExposesReviewedFieldsAndRetainsUnknownValues() throws {
    let fixture = try XCTUnwrap(
      Bundle.module.url(forResource: "campaign-v26", withExtension: "json"))
    let campaign = try JSONDecoder().decode(Campaign.self, from: Data(contentsOf: fixture))
    XCTAssertEqual(campaign.id, "42")
    XCTAssertEqual(campaign.accountID, "act_7")
    XCTAssertEqual(campaign.objective, "OUTCOME_TRAFFIC")
    XCTAssertEqual(campaign.buyingType, "AUCTION")
    XCTAssertEqual(campaign.createdTime, "2026-01-01T00:00:00+0000")
    XCTAssertEqual(campaign.status, .unknown("FUTURE_STATUS"))
    guard case .number = campaign.additionalFields["future_metric"]?.storage else {
      return XCTFail("unknown fixture value was not retained")
    }
  }

  func testCapabilityAndFieldMatricesStayBoundToTypedReaderDispatch() throws {
    let descriptors = MetaAdsCapabilityCatalog.descriptors
    XCTAssertEqual(descriptors.count, 11)
    XCTAssertEqual(Set(descriptors.map(\.operationID)).count, descriptors.count)
    XCTAssertEqual(MetaAdsCapabilityCatalog.operationIDs, descriptors.map(\.operationID))
    for descriptor in descriptors where descriptor.kind == .list {
      XCTAssertEqual(
        MetaAdsCapabilityCatalog.listDescriptor(for: descriptor.cliSubject), descriptor)
      XCTAssertFalse(MetaAdsFieldMatrix.fields(for: descriptor.domain).isEmpty)
      XCTAssertNoThrow(
        try FieldSelection(
          [MetaAdsFieldMatrix.fields(for: descriptor.domain)[0]], domain: descriptor.domain))
    }
    XCTAssertNil(MetaAdsCapabilityCatalog.listDescriptor(for: "not-a-domain"))
    XCTAssertThrowsError(try FieldSelection(["not_a_reviewed_field"], domain: .campaign))
  }
}
