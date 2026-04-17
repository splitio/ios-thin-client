import XCTest
@testable import SplitThin

final class DelayProviderTest: XCTestCase {

    private let delayProvider = buildDelayProvider()

    func testReturnsZeroWithNilNotification() {
        let delay = delayProvider(nil, "user1")
        XCTAssertEqual(delay, 0)
    }

    func testReturnsZeroWhenUpdateIntervalMsIsMissing() {
        let notification = EvaluationUpdateNotification(channel: nil, timestamp: 0, changeNumber: 1,
                                                        updateIntervalMs: nil, algorithmSeed: 42)
        let delay = delayProvider(notification, "user1")
        XCTAssertEqual(delay, 0)
    }

    func testReturnsZeroWhenAlgorithmSeedIsMissing() {
        let notification = EvaluationUpdateNotification(channel: nil, timestamp: 0, changeNumber: 1,
                                                        updateIntervalMs: 5000, algorithmSeed: nil)
        let delay = delayProvider(notification, "user1")
        XCTAssertEqual(delay, 0)
    }

    func testReturnsComputedDelayWhenNotificationIsComplete() {
        let intervalMs: Int64 = 5000
        let seed = 42
        let notification = EvaluationUpdateNotification(channel: nil, timestamp: 0, changeNumber: 1,
                                                        updateIntervalMs: intervalMs, algorithmSeed: seed)
        let delay = delayProvider(notification, "user1")

        let hash = Murmur3Hash.hashString("user1", UInt32(truncatingIfNeeded: seed))
        let expectedMs = Int64(hash) % intervalMs
        let expectedDelay = Double(expectedMs < 0 ? -expectedMs : expectedMs) / 1000.0

        XCTAssertEqual(delay, expectedDelay, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(delay, 0)
        XCTAssertLessThan(delay, Double(intervalMs) / 1000.0)
    }

    func testDelayIsAlwaysWithinInterval() {
        let intervalMs: Int64 = 3000
        let notification = EvaluationUpdateNotification(channel: nil, timestamp: 0, changeNumber: 1,
                                                        updateIntervalMs: intervalMs, algorithmSeed: 99)
        let keys = ["user1", "user2", "user3", "abc", "xyz"]
        for key in keys {
            let delay = delayProvider(notification, key)
            XCTAssertGreaterThanOrEqual(delay, 0, "Delay must be non-negative for key \(key)")
            XCTAssertLessThan(delay, Double(intervalMs) / 1000.0, "Delay must be less than interval for key \(key)")
        }
    }
}
