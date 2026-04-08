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

    private let onReadyExpectation: XCTestExpectation?
    private let onTimedOutExpectation: XCTestExpectation?
    private let onUpdateExpectation: XCTestExpectation?

    init(onReadyExpectation: XCTestExpectation? = nil, onTimedOutExpectation: XCTestExpectation? = nil, onUpdateExpectation: XCTestExpectation? = nil) {
        self.onReadyExpectation = onReadyExpectation
        self.onTimedOutExpectation = onTimedOutExpectation
        self.onUpdateExpectation = onUpdateExpectation
    }

    func onReady(_ metadata: SdkReadyMetadata) {
        onReadyCallCount += 1
        lastReadyMetadata = metadata
        onReadyExpectation?.fulfill()
    }

    func onReadyFromCache(_ metadata: SdkReadyFromCacheMetadata) {
        onReadyFromCacheCallCount += 1
        lastReadyFromCacheMetadata = metadata
    }

    func onReadyTimedOut() {
        onReadyTimedOutCallCount += 1
        onTimedOutExpectation?.fulfill()
    }

    func onUpdate(_ metadata: SdkUpdateMetadata) {
        onUpdateCallCount += 1
        lastUpdateMetadata = metadata
        onUpdateExpectation?.fulfill()
    }
}
