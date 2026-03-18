import Foundation

public struct EvaluationOptions: Sendable {
    public let properties: [String: String]?

    public init(properties: [String: String]? = nil) {
        self.properties = properties
    }
}
