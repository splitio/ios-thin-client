import Foundation

enum Version {
    private static let kSdkPlatform = "ios-thin"
    private static let kVersion = "0.1.0"

    static var semantic: String {
        kVersion
    }

    static var sdk: String {
        "\(kSdkPlatform)-\(kVersion)"
    }
}
