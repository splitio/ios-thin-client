import XCTest
@testable import SplitThin

final class RolloutCacheConfigurationTests: XCTestCase {

    func testDefaultValues() {
        let config = RolloutCacheConfiguration.builder().build()

        XCTAssertEqual(config.expirationDays, 10)
        XCTAssertEqual(config.clearOnInit, false)
    }

    func testExpirationIsCorrectlySet() {
        let config = RolloutCacheConfiguration.builder().set(expirationDays: 1).build()
        XCTAssertEqual(config.expirationDays, 1)
    }

    func testClearOnInitIsCorrectlySet() {
        let config = RolloutCacheConfiguration.builder().set(clearOnInit: true).build()
        XCTAssertEqual(config.clearOnInit, true)
    }

    func testExpirationBelowMinimumFallsBackToDefault() {
        let config = RolloutCacheConfiguration.builder().set(expirationDays: 0).build()
        XCTAssertEqual(config.expirationDays, 10)
    }

    func testNegativeExpirationFallsBackToDefault() {
        let config = RolloutCacheConfiguration.builder().set(expirationDays: -1).build()
        XCTAssertEqual(config.expirationDays, 10)
    }
}
