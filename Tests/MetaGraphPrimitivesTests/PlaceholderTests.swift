import XCTest

@testable import MetaGraphPrimitives

final class PlaceholderTests: XCTestCase {
  func testPrimitiveTargetBuildsIndependently() throws { _ = try GraphAPIVersion("v25.0") }
}
