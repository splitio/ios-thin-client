import Foundation

@discardableResult
func withLock<T>(_ lock: NSLock, _ block: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return block()
}

extension Array {
    mutating func removeElementByMemoryAddress(_ element: Element) {
        let targetId = ObjectIdentifier(element as AnyObject)
        if let index = firstIndex(where: { ObjectIdentifier($0 as AnyObject) == targetId }) {
            remove(at: index)
        }
    }
}
