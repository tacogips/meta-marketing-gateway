import XCTest

@testable import MetaTrustedHeadProtocol

final class TrustedHeadProtocolTests: XCTestCase {
  func testHeadRejectsMalformedDigest() {
    XCTAssertThrowsError(try TrustedHead(sequence: 1, digest: "x"))
  }

  func testWireRequestRejectsUnsafeNamespaceAndInvalidCASShape() {
    let digest = String(repeating: "a", count: 64)
    XCTAssertThrowsError(
      try TrustedHeadWireRequest(
        operation: "readHead", namespace: "../state", recordIdentity: digest))
    XCTAssertThrowsError(
      try TrustedHeadWireRequest(
        operation: "compareAndSetHead", namespace: "safe", recordIdentity: digest))
  }

  func testWireRequestIsBoundedAndVersioned() throws {
    let digest = String(repeating: "a", count: 64)
    let head = try TrustedHead(sequence: 1, digest: digest)
    let request = try TrustedHeadWireRequest(
      operation: "compareAndSetHead", namespace: "writer-1", recordIdentity: digest,
      expected: nil, proposed: head)
    XCTAssertEqual(try request.validated(), request)
  }
}
