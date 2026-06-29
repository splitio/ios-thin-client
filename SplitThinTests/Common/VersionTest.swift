import XCTest
@testable import SplitThin

final class VersionTest: XCTestCase {

    func testSemanticVersionIsValidSemVer() {
        let semantic = Version.semantic

        // major.minor.patch with optional pre-release / build metadata (SemVer)
        let pattern = #"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$"#
        XCTAssertNotNil(semantic.range(of: pattern, options: .regularExpression),
                        "Version.semantic '\(semantic)' is not a valid semantic version")

        // The major.minor.patch core must have 3 numeric components
        let core = semantic.split(separator: "-")[0]
        XCTAssertEqual(3, core.split(separator: ".").count)
    }

    func testSdkVersionHasPlatformPrefix() {
        let sdk = Version.sdk
        XCTAssertTrue(sdk.hasPrefix("iOSThin-"), "Version.sdk '\(sdk)' should start with 'iOSThin-'")
        XCTAssertEqual("iOSThin-\(Version.semantic)", sdk)
    }
}
