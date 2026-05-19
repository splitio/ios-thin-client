import XCTest
@testable import SplitThin

final class DelayProviderTest: XCTestCase {

    func testNoIntervalReturnsZero() {
        let delay = computeKeyDelay(matchingKey: "user1", delay: .none)
        XCTAssertEqual(delay, 0)
    }

    func testZeroIntervalReturnsZero() {
        let delay = computeKeyDelay(matchingKey: "user1", delay: RefetchDelay(intervalMs: 0, seed: 42))
        XCTAssertEqual(delay, 0)
    }

    func testDelayIsWithinInterval() {
        let intervalMs: Int64 = 5000
        let delay = computeKeyDelay(matchingKey: "user1", delay: RefetchDelay(intervalMs: intervalMs, seed: 42))
        XCTAssertGreaterThanOrEqual(delay, 0)
        XCTAssertLessThan(delay, Double(intervalMs) / 1000.0)
    }

    func testDifferentSeedsProduceDifferentDelays() {
        let delay1 = computeKeyDelay(matchingKey: "user1", delay: RefetchDelay(intervalMs: 60000, seed: 1))
        let delay2 = computeKeyDelay(matchingKey: "user1", delay: RefetchDelay(intervalMs: 60000, seed: 2))
        // Different seeds should (with very high probability) produce different delays
        XCTAssertNotEqual(delay1, delay2)
    }

    func testSameInputProducesDeterministicDelay() {
        let d = RefetchDelay(intervalMs: 60000, seed: 42)
        let delay1 = computeKeyDelay(matchingKey: "user1", delay: d)
        let delay2 = computeKeyDelay(matchingKey: "user1", delay: d)
        XCTAssertEqual(delay1, delay2)
    }

    func testDifferentKeysSpreadAcrossInterval() {
        let intervalMs: Int64 = 60000
        let d = RefetchDelay(intervalMs: intervalMs, seed: 0)
        let keys = ["user1", "user2", "user3", "user4", "user5", "user6", "user7", "user8", "user9", "user10"]
        let delays = Set(keys.map { computeKeyDelay(matchingKey: $0, delay: d) })

        // At least some keys should get different delays
        XCTAssertGreaterThan(delays.count, 1)
    }
}
