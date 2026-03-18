import Foundation

enum Version {
    private static let sdkPlatform = "ios-thin"
    private static let version = "0.1.0"

    static var semantic: String {
        version
    }

    static var sdk: String {
        "\(sdkPlatform)-\(version)"
    }
}
