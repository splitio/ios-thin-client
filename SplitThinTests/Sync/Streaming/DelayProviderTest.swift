import XCTest
@testable import SplitThin

final class DelayProviderTest: XCTestCase {

    func testNoIntervalReturnsZero() {
        let delay = RefetchDelay.none.delay(forKey: "user1")
        XCTAssertEqual(delay, 0)
    }

    func testZeroIntervalReturnsZero() {
        let delay = RefetchDelay(intervalMs: 0, seed: 42).delay(forKey: "user1")
        XCTAssertEqual(delay, 0)
    }

    func testDelayIsWithinInterval() {
        let intervalMs: Int64 = 5000
        let delay = RefetchDelay(intervalMs: intervalMs, seed: 42).delay(forKey: "user1")
        XCTAssertGreaterThanOrEqual(delay, Double(RefetchDelay.minDelayMs) / 1000.0)
        XCTAssertLessThan(delay, Double(intervalMs) / 1000.0)
    }

    func testDelayRespectsMinimumFloor() {
        let d = RefetchDelay(intervalMs: 60000, seed: 0)
        let floor = Double(RefetchDelay.minDelayMs) / 1000.0
        let keys = ["user1", "user2", "user3", "user4", "user5", "user6", "user7", "user8", "user9", "user10"]
        for key in keys {
            XCTAssertGreaterThanOrEqual(d.delay(forKey: key), floor)
        }
    }

    func testIntervalBelowMinimumReturnsInterval() {
        let intervalMs: Int64 = 300
        let delay = RefetchDelay(intervalMs: intervalMs, seed: 42).delay(forKey: "user1")
        XCTAssertEqual(delay, Double(intervalMs) / 1000.0)
    }

    func testIntervalEqualToMinimumReturnsInterval() {
        let delay = RefetchDelay(intervalMs: RefetchDelay.minDelayMs, seed: 42).delay(forKey: "user1")
        XCTAssertEqual(delay, Double(RefetchDelay.minDelayMs) / 1000.0)
    }

    func testDifferentSeedsProduceDifferentDelays() {
        let delay1 = RefetchDelay(intervalMs: 60000, seed: 1).delay(forKey: "user1")
        let delay2 = RefetchDelay(intervalMs: 60000, seed: 2).delay(forKey: "user1")
        // Different seeds should (with very high probability) produce different delays
        XCTAssertNotEqual(delay1, delay2)
    }

    func testSameInputProducesDeterministicDelay() {
        let d = RefetchDelay(intervalMs: 60000, seed: 42)
        let delay1 = d.delay(forKey: "user1")
        let delay2 = d.delay(forKey: "user1")
        XCTAssertEqual(delay1, delay2)
    }

    func testDifferentKeysSpreadAcrossInterval() {
        let intervalMs: Int64 = 60000
        let d = RefetchDelay(intervalMs: intervalMs, seed: 0)
        let keys = ["user1", "user2", "user3", "user4", "user5", "user6", "user7", "user8", "user9", "user10"]
        let delays = Set(keys.map { d.delay(forKey: $0) })

        // At least some keys should get different delays
        XCTAssertGreaterThan(delays.count, 1)
    }
}
