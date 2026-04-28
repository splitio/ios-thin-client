import XCTest
@testable import SplitThin

class DefaultStreamingTest: XCTestCase {

    var managerMock: StreamingConnectionManagerMock!
    var streamingManager: DefaultStreamingManager!
    var streaming: DefaultStreaming!

    override func setUp() {
        super.setUp()
        managerMock = StreamingConnectionManagerMock()
        streamingManager = DefaultStreamingManager { [unowned self] in managerMock }
        streaming = DefaultStreaming(streamingManager: streamingManager)
    }

    func testStartDelegatesToManager() async {
        await streaming.start()
        XCTAssertEqual(managerMock.startCallCount, 1)
    }

    func testStopDelegatesToManager() async {
        streamingManager.start()
        await streaming.stop()
        XCTAssertEqual(managerMock.stopCallCount, 1)
    }

    func testPauseDelegatesToManager() {
        streamingManager.start()
        streaming.pause()
        XCTAssertEqual(managerMock.pauseCallCount, 1)
    }

    func testResumeDelegatesToManager() {
        streamingManager.start()
        streaming.resume()
        XCTAssertEqual(managerMock.resumeCallCount, 1)
    }
}
