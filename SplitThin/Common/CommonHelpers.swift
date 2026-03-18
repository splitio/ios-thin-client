import Foundation

@discardableResult
func withLock<T>(_ lock: NSLock, _ block: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return block()
}
