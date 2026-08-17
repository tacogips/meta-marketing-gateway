import XCTest

@testable import MetaCapabilityCatalogGenerator

final class CatalogGeneratorTests: XCTestCase {
  func testGeneratorRejectsDuplicateIDsAndReaderMutations() throws {
    let duplicate =
      #"{"schema":1,"reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","operations":[{"id":"meta.graph.get","surface":"reader","kind":"publicRead","method":"GET","path":"relative","version":"validated","implementation":"generic","reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","availability":"enabled"},{"id":"meta.graph.get","surface":"reader","kind":"publicRead","method":"GET","path":"relative","version":"validated","implementation":"generic","reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","availability":"enabled"}]}"#
    XCTAssertThrowsError(try CatalogGenerator.load(Data(duplicate.utf8)))

    let mutation =
      #"{"schema":1,"reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","operations":[{"id":"meta.graph.get","surface":"reader","kind":"publicRead","method":"POST","path":"relative","version":"validated","implementation":"generic","reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","availability":"enabled"}]}"#
    XCTAssertThrowsError(try CatalogGenerator.load(Data(mutation.utf8)))
  }

  func testProjectionIsDeterministicAndSurfaceLimited() throws {
    let source =
      #"{"schema":1,"reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","operations":[{"id":"meta.generic.write","surface":"writer","kind":"mutation","method":"POST","path":"relative","version":"validated","implementation":"generic","reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","availability":"denied","reason":"offline only","blockers":["rolloutPolicy"]},{"id":"meta.graph.get","surface":"reader","kind":"publicRead","method":"GET","path":"relative","version":"validated","implementation":"generic","reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","availability":"enabled"}]}"#
    let manifest = try CatalogGenerator.load(Data(source.utf8))
    XCTAssertEqual(
      try CatalogGenerator.swiftProjection(manifest: manifest, surface: "reader"),
      try CatalogGenerator.swiftProjection(manifest: manifest, surface: "reader"))
    XCTAssertFalse(
      try CatalogGenerator.swiftProjection(manifest: manifest, surface: "reader").contains(
        "meta.generic.write"))
  }

  func testGeneratorRejectsMissingWriterBlockerAndUnreviewedSource() {
    let incomplete =
      #"{"schema":1,"reviewDate":"2026-08-15","source":"http://example.test","operations":[{"id":"meta.generic.write","surface":"writer","kind":"mutation","method":"POST","path":"relative","version":"validated","implementation":"generic","reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","availability":"denied"}]}"#
    XCTAssertThrowsError(try CatalogGenerator.load(Data(incomplete.utf8)))
  }

  func testGeneratorRequiresPerOperationReviewAndAvailabilityPrecedence() {
    let missingOperationReview =
      #"{"schema":1,"reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","operations":[{"id":"meta.graph.get","surface":"reader","kind":"publicRead","method":"GET","path":"relative","version":"validated","implementation":"generic","availability":"enabled"}]}"#
    XCTAssertThrowsError(try CatalogGenerator.load(Data(missingOperationReview.utf8)))

    let providerProofWithoutAuthoritativeReason =
      #"{"schema":1,"reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","operations":[{"id":"meta.generic.write","surface":"writer","kind":"mutation","method":"POST","path":"relative","version":"validated","implementation":"generic","reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","availability":"blockedProviderProof","reason":"provider label required"}]}"#
    XCTAssertThrowsError(
      try CatalogGenerator.load(Data(providerProofWithoutAuthoritativeReason.utf8)))

    let staleReview =
      #"{"schema":1,"reviewDate":"2026-08-14","source":"https://developers.facebook.com/docs","operations":[{"id":"meta.graph.get","surface":"reader","kind":"publicRead","method":"GET","path":"relative","version":"validated","implementation":"generic","reviewDate":"2026-08-14","source":"https://developers.facebook.com/docs","availability":"enabled"}]}"#
    XCTAssertThrowsError(try CatalogGenerator.load(Data(staleReview.utf8)))

    let providerProofWithOutstandingContract =
      #"{"schema":1,"reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","operations":[{"id":"meta.generic.write","surface":"writer","kind":"mutation","method":"POST","path":"relative","version":"validated","implementation":"generic","reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","availability":"blockedProviderProof","reason":"authoritative proof missing","blockers":["missingMachineVerifiableAssetClassification","missingReconcilerContract"]}]}"#
    XCTAssertThrowsError(
      try CatalogGenerator.load(Data(providerProofWithOutstandingContract.utf8)))

    let versionReviewWithPolicyBlocker =
      #"{"schema":1,"reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","operations":[{"id":"meta.generic.write","surface":"writer","kind":"mutation","method":"POST","path":"relative","version":"validated","implementation":"generic","reviewDate":"2026-08-15","source":"https://developers.facebook.com/docs","availability":"blockedVersionReview","reason":"review incomplete","blockers":["rolloutPolicy","missingReconcilerContract"]}]}"#
    XCTAssertThrowsError(
      try CatalogGenerator.load(Data(versionReviewWithPolicyBlocker.utf8)))
  }
}
