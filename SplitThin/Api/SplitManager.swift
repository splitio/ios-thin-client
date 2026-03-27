import Foundation

public protocol SplitManager: AnyObject {
    func getFlagNames() -> [String]
}

final class DefaultSplitManager: SplitManager {

    private var flagNames = [String]()
    private let lock = NSLock()

    func getFlagNames() -> [String] {
        withLock(lock) { flagNames }
    }

    func updateFlags(_ flags: [String]) {
        withLock(lock) {
            for flag in flags where !flagNames.contains(flag) {
                flagNames.append(flag)
            }
        }
    }
}
