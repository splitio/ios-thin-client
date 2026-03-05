import XCTest
@testable import SplitThin

final class DefaultSplitFactoryBuilderTest: XCTestCase {

    func testBuildWithNoParams() {
        let factory = DefaultSplitFactoryBuilder().build()

        XCTAssertNil(factory, "Factory should be nil when no params are set")
    }

    func testBuildWithEmptyApiKey() {
        let factory = DefaultSplitFactoryBuilder()
            .setApiKey("")
            .setTarget(Target(matchingKey: "user1"))
            .build()

        XCTAssertNil(factory, "Factory should be nil with empty API key")
    }

    func testBuildWithNoTarget() {
        let factory = DefaultSplitFactoryBuilder()
            .setApiKey("api-key-123")
            .build()

        XCTAssertNil(factory, "Factory should be nil when target is missing")
    }

    func testBuildWithEmptyMatchingKey() {
        let factory = DefaultSplitFactoryBuilder()
            .setApiKey("api-key-123")
            .setTarget(Target(matchingKey: ""))
            .build()

        XCTAssertNil(factory, "Factory should be nil with empty matching key")
    }

    func testBuildSuccess() {
        let factory = DefaultSplitFactoryBuilder()
            .setApiKey("api-key-123")
            .setTarget(Target(matchingKey: "user1"))
            .build()

        XCTAssertNotNil(factory, "Factory should not be nil with valid params")
    }

    func testBuildSuccessWithAllParams() {
        let filters = EvaluationFilters(flagNames: ["flag_a"], flagSets: ["set_1"])
        let target = Target(matchingKey: "user1", bucketingKey: "bk1",
                            attributes: ["env": "prod"], trafficType: "user")

        let factory = DefaultSplitFactoryBuilder()
            .setApiKey("api-key-123")
            .setTarget(target)
            .setEvaluationFilters(filters)
            .build()

        XCTAssertNotNil(factory, "Factory should not be nil with all params")
    }

    func testFluentApiReturnsSelf() {
        let builder = DefaultSplitFactoryBuilder()

        let b1 = builder.setApiKey("key")
        let b2 = b1.setTarget(Target(matchingKey: "user1"))
        let b3 = b2.setEvaluationFilters(EvaluationFilters())

        XCTAssertNotNil(b3.build())
    }
}
