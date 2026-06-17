import XCTest
@testable import SplitThin

final class CacheValidatorTests: XCTestCase {

    // MARK: - fingerprint

    func testFingerprintIsStableForSameInputs() {
        let validator = DefaultCacheValidator(configsEnabled: true)
        let target = Target(matchingKey: "user", attributes: ["plan": "pro"], trafficType: "user")

        XCTAssertEqual(validator.fingerprint(for: target), validator.fingerprint(for: target))
    }

    func testFingerprintDiffersWhenConfigsEnabledDiffers() {
        let target = Target(matchingKey: "user", attributes: ["plan": "pro"], trafficType: "user")

        let disabled = DefaultCacheValidator(configsEnabled: false).fingerprint(for: target)
        let enabled = DefaultCacheValidator(configsEnabled: true).fingerprint(for: target)

        XCTAssertNotEqual(disabled, enabled)
    }

    func testFingerprintDiffersWhenAttributesDiffer() {
        let validator = DefaultCacheValidator(configsEnabled: true)

        let pro = validator.fingerprint(for: Target(matchingKey: "user", attributes: ["plan": "pro"], trafficType: "user"))
        let free = validator.fingerprint(for: Target(matchingKey: "user", attributes: ["plan": "free"], trafficType: "user"))

        XCTAssertNotEqual(pro, free)
    }

    // MARK: - isValid

    func testIsValidWhenNoStoredFingerprint() {
        let validator = DefaultCacheValidator(configsEnabled: true)
        let target = Target(matchingKey: "user", trafficType: "user")

        XCTAssertTrue(validator.isValid(storedAttrHash: nil, for: target))
    }

    func testIsValidWhenStoredFingerprintMatches() {
        let validator = DefaultCacheValidator(configsEnabled: true)
        let target = Target(matchingKey: "user", attributes: ["plan": "pro"], trafficType: "user")

        let stored = validator.fingerprint(for: target)

        XCTAssertTrue(validator.isValid(storedAttrHash: stored, for: target))
    }

    func testIsInvalidWhenConfigsEnabledChanged() {
        let target = Target(matchingKey: "user", attributes: ["plan": "pro"], trafficType: "user")
        let storedWhileDisabled = DefaultCacheValidator(configsEnabled: false).fingerprint(for: target)

        let enabled = DefaultCacheValidator(configsEnabled: true)

        XCTAssertFalse(enabled.isValid(storedAttrHash: storedWhileDisabled, for: target))
    }
}
