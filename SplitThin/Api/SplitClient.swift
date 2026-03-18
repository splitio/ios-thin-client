import Foundation

public protocol SplitClient: AnyObject {
    var target: Target { get }
    func destroy()
}
