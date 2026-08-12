import Foundation
import XCTest
@testable import SplitThin

func withLock<T>(_ lock: NSLock, _ block: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return block()
}

func sleep(seconds: Double) {
    Thread.sleep(forTimeInterval: seconds)
}

extension XCTestCase {

    func expectation(_ description: String = #function) -> XCTestExpectation {
        expectation(description: description)
    }

    // Utility to improve testing legibility. 
    // self and expectations are boxed because XCTestCase/XCTestExpectation aren't Sendable, but
    // XCTest runs test methods serially, so sending them into this Task is safe.
    func waitFor(_ expectations: XCTestExpectation..., timeout: Double = 3) {
        let testCase = UncheckedSendableBox(value: self)
        let expectations = UncheckedSendableBox(value: expectations)
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await testCase.value.fulfillment(of: expectations.value, timeout: timeout)
            semaphore.signal()
        }
        semaphore.wait()
    }

    func waitUntil(timeout: Double = 3, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            sleep(seconds: 0.02)
        }
    }
}

extension XCTestExpectation {
    func inverted() -> XCTestExpectation {
        isInverted = true
        return self
    }
}