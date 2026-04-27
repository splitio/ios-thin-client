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
    // If the expectation doesn't fulfill in 3 seconds, THE TEST FAILS.
    func waitFor(_ expectations: XCTestExpectation..., timeout: Double = 3) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await fulfillment(of: expectations, timeout: timeout)
            semaphore.signal()
        }
        semaphore.wait()
    }
}

extension XCTestExpectation {
    func inverted() -> XCTestExpectation {
        isInverted = true
        return self
    }
}