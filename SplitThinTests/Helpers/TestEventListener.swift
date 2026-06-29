import Foundation
import XCTest
@testable import SplitThin

final class TestEventListener: SplitEventListener, @unchecked Sendable {
    var onReadyCallCount = 0
    var onReadyFromCacheCallCount = 0
    var onReadyTimedOutCallCount = 0
    var onUpdateCallCount = 0

    var lastReadyMetadata: SdkReadyMetadata?
    var lastReadyFromCacheMetadata: SdkReadyFromCacheMetadata?
    var lastUpdateMetadata: SdkUpdateMetadata?

    private let readyExpectation: XCTestExpectation?
    private let timeoutExpectation: XCTestExpectation?
    private let updateExpectation: XCTestExpectation?
    private let cacheExpectation: XCTestExpectation?

    init(readyExpectation: XCTestExpectation? = nil, timeoutExpectation: XCTestExpectation? = nil, updateExpectation: XCTestExpectation? = nil, cacheExpectation: XCTestExpectation? = nil) {
        self.readyExpectation = readyExpectation
        self.timeoutExpectation = timeoutExpectation
        self.updateExpectation = updateExpectation
        self.cacheExpectation = cacheExpectation
    }

    func onReady(_ metadata: SdkReadyMetadata) {
        onReadyCallCount += 1
        lastReadyMetadata = metadata
        readyExpectation?.fulfill()
    }

    func onReadyFromCache(_ metadata: SdkReadyFromCacheMetadata) {
        onReadyFromCacheCallCount += 1
        lastReadyFromCacheMetadata = metadata
        cacheExpectation?.fulfill()
    }

    func onReadyTimedOut() {
        onReadyTimedOutCallCount += 1
        timeoutExpectation?.fulfill()
    }

    func onUpdate(_ metadata: SdkUpdateMetadata) {
        onUpdateCallCount += 1
        lastUpdateMetadata = metadata
        updateExpectation?.fulfill()
    }
}
