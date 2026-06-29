import XCTest
@testable import SplitThin

/// This is a ThreadSanitizer driver, not an assertion-based test
/// Run with: swift test --sanitize=thread --filter StreamingDataRaceTest
///
/// To validate: revert the fix (remove the lock around
/// `activeConnectionHandler` in stop()/pause()/reportError()/connectSse) and TSan reports a data race.

final class StreamingDataRaceTest: XCTestCase {

    private let iterations = 50

    func testConcurrentLifecycleHasNoDataRaceOnConnectionHandler() {
        for _ in 0..<iterations {
            let cm = DefaultStreaming.makeForTest()
            let group = DispatchGroup()

            // Side A: start() spawns connectSse, which writes activeConnectionHandler.
            group.enter()
            DispatchQueue.global().async {
                cm.start()
                group.leave()
            }

            // Side B: a non-retryable error reads activeConnectionHandler and clears it.
            group.enter()
            DispatchQueue.global().async {
                cm.reportError(isRetryable: false)
                group.leave()
            }

            group.wait()
            // Give connectSse's Task time to land its write while cm is still alive, so the
            // racing accesses overlap. stop() adds one more read+clear participant.
            Thread.sleep(forTimeInterval: 0.003)
            cm.stop()
        }
    }
}
