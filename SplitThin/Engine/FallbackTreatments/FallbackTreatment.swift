import Foundation

/// A fallback treatment configuration for a feature flag.
///
/// Used to define fallback treatments at the factory level (global)
/// or per individual flag.
public struct FallbackTreatment: Sendable {

    public let treatment: String
    public let config: String?
    let label: String?

    /// Initializes a new FallbackTreatment instance.
    /// - Parameters:
    ///   - treatment: The treatment String to use as fallback.
    ///   - config: Optional dynamic configuration String for the treatment.
    public init(treatment: String, config: String? = nil) {
        self.treatment = treatment
        self.config = config
        self.label = nil
    }

    init(treatment: String, config: String? = nil, label: String? = nil) {
        self.treatment = treatment
        self.config = config
        self.label = label
    }
}

// This extension enables mixed treatment expressions.
// (i.e.  ["flag1": FallbackTreatment(treatment: "on"), "flag2": "off"]
extension FallbackTreatment: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(treatment: value)
    }
}
