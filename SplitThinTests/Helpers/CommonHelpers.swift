import Foundation
import XCTest

func withLock<T>(_ lock: NSLock, _ block: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return block()
}

func sleep(seconds: Double) {
    Thread.sleep(forTimeInterval: seconds)
}

extension XCTestCase {
    
    // Utility to improve testing legibility. Timeout of 3 seconds by default.
    func waitFor(_ expectations: XCTestExpectation..., timeout: Double = 3) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await fulfillment(of: expectations, timeout: timeout)
            semaphore.signal()
        }
        semaphore.wait()
    }
}
