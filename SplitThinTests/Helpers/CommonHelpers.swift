import Foundation
import XCTest
@testable import SplitThin

// XCTest runs one test method at a time, so treating test cases as Sendable is safe and
// avoids having to annotate every test class that captures `self` in a Task/async let.
extension XCTestCase: @retroactive @unchecked Sendable {}

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
    // If the expectation doesn't fulfill in 3 seconds, THE TEST FAILS.
    func waitFor(_ expectations: XCTestExpectation..., timeout: Double = 3) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await fulfillment(of: expectations, timeout: timeout)
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