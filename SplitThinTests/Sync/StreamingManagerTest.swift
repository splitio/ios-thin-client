import XCTest
@testable import SplitThin

class StreamingManagerTest: XCTestCase {

    var connectionManagerMock: StreamingConnectionManagerMock!
    var manager: DefaultStreamingManager!

    override func setUp() {
        super.setUp()
        connectionManagerMock = StreamingConnectionManagerMock()
        manager = DefaultStreamingManager { [unowned self] in connectionManagerMock }
    }

    func testStartCreatesAndStartsConnectionManager() {
        manager.start()
        XCTAssertEqual(connectionManagerMock.startCallCount, 1)
    }

    func testStartTwiceUsesTheSameConnectionManager() {
        manager.start()
        manager.start()
        XCTAssertEqual(connectionManagerMock.startCallCount, 2)
    }

    func testStopCallsConnectionManager() {
        manager.start()
        manager.stop()
        XCTAssertEqual(connectionManagerMock.stopCallCount, 1)
    }

    func testStopBeforeStartDoesNotCrash() {
        manager.stop() // no connection manager yet — should be a no-op
        XCTAssertEqual(connectionManagerMock.stopCallCount, 0)
    }

    func testPauseCallsConnectionManager() {
        manager.start()
        manager.pause()
        XCTAssertEqual(connectionManagerMock.pauseCallCount, 1)
    }

    func testResumeCallsConnectionManager() {
        manager.start()
        manager.resume()
        XCTAssertEqual(connectionManagerMock.resumeCallCount, 1)
    }

    func testStopAllNilsOutConnectionManager() {
        manager.start()
        manager.stopAll()
        XCTAssertEqual(connectionManagerMock.stopCallCount, 1)
        // After stopAll, stop/pause/resume are no-ops
        manager.stop()
        XCTAssertEqual(connectionManagerMock.stopCallCount, 1)
    }
}
