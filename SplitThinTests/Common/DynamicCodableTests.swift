import XCTest
@testable import SplitThin

final class ParsingTest: XCTestCase {

    // MARK: - AuthResponse

    func testAuthResponseParsesValidJson() throws {
        let json = """
        {"token":"eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3NzMzNTUzODR9.sig","pushEnabled":true,"connDelay":5}
        """.data(using: .utf8)!

        let response = try Json.decode(from: json, to: AuthResponse.self)

        XCTAssertEqual(response.token, "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3NzMzNTUzODR9.sig")
        XCTAssertTrue(response.pushEnabled)
        XCTAssertEqual(response.connDelay, 5)
    }

    func testAuthResponseParsesWithoutConnDelay() throws {
        let json = """
        {"token":"jwt-token","pushEnabled":false}
        """.data(using: .utf8)!

        let response = try Json.decode(from: json, to: AuthResponse.self)

        XCTAssertEqual(response.token, "jwt-token")
        XCTAssertFalse(response.pushEnabled)
        XCTAssertNil(response.connDelay)
    }

    func testAuthResponseThrowsOnMissingToken() {
        let json = """
        {"pushEnabled":true}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: AuthResponse.self))
    }

    func testAuthResponseDefaultsPushEnabledToFalse() throws {
        let json = """
        {"token":"jwt-token"}
        """.data(using: .utf8)!

        let response = try Json.decode(from: json, to: AuthResponse.self)
        XCTAssertFalse(response.pushEnabled)
        XCTAssertNil(response.connDelay)
    }

    func testAuthResponseThrowsOnInvalidJson() {
        let json = "not valid json".data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: AuthResponse.self))
    }

    // MARK: - EvaluationResult

    func testEvaluationResultParsesValidJson() throws {
        let json = """
        {"featureName":"my_flag","treatment":"on","sets":["set1","set2"],"config":"{\\"key\\":\\"value\\"}","label":"default rule","changeNumber":12345}
        """.data(using: .utf8)!

        let result = try Json.decode(from: json, to: EvaluationResult.self)

        XCTAssertEqual(result.flag, "my_flag")
        XCTAssertEqual(result.treatment, "on")
        XCTAssertEqual(result.flagSets, ["set1", "set2"])
        XCTAssertEqual(result.config, "{\"key\":\"value\"}")
        XCTAssertEqual(result.changeNumber, 12345)
    }

    func testEvaluationResultParsesMinimalJson() throws {
        let json = """
        {"featureName":"flag","treatment":"off","sets":[]}
        """.data(using: .utf8)!

        let result = try Json.decode(from: json, to: EvaluationResult.self)

        XCTAssertEqual(result.flag, "flag")
        XCTAssertEqual(result.treatment, "off")
        XCTAssertEqual(result.flagSets, [])
        XCTAssertNil(result.config)
        XCTAssertNil(result.changeNumber)
    }

    func testEvaluationResultThrowsOnMissingFeatureName() {
        let json = """
        {"treatment":"on","sets":[]}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: EvaluationResult.self))
    }

    func testEvaluationResultThrowsOnMissingTreatment() {
        let json = """
        {"featureName":"flag","sets":[]}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: EvaluationResult.self))
    }

    // MARK: - EvaluationsResult

    func testEvaluationsResultParsesValidJson() throws {
        let json = """
        {"since":-1,"till":1772129027764,"evaluations":[{"featureName":"flag1","treatment":"on","sets":[]},{"featureName":"flag2","treatment":"off","sets":["setA"]}]}
        """.data(using: .utf8)!

        let result = try Json.decode(from: json, to: EvaluationsResult.self)

        XCTAssertEqual(result.since, -1)
        XCTAssertEqual(result.till, 1772129027764)
        XCTAssertEqual(result.evaluations.count, 2)
        XCTAssertEqual(result.evaluations[0].flag, "flag1")
        XCTAssertEqual(result.evaluations[0].treatment, "on")
        XCTAssertEqual(result.evaluations[1].flag, "flag2")
        XCTAssertEqual(result.evaluations[1].treatment, "off")
        XCTAssertEqual(result.evaluations[1].flagSets, ["setA"])
    }

    func testEvaluationsResultParsesEmptyEvaluations() throws {
        let json = """
        {"since":0,"till":100,"evaluations":[]}
        """.data(using: .utf8)!

        let result = try Json.decode(from: json, to: EvaluationsResult.self)

        XCTAssertEqual(result.evaluations.count, 0)
    }

    func testEvaluationsResultParsesMissingEvaluationsAsEmpty() throws {
        let json = """
        {"since":0,"till":100}
        """.data(using: .utf8)!

        let result = try Json.decode(from: json, to: EvaluationsResult.self)

        XCTAssertEqual(result.evaluations.count, 0)
    }

    func testEvaluationsResultParsesWithNullSinceAndTill() throws {
        let json = """
        {"since":null,"till":null,"evaluations":[{"featureName":"flag","treatment":"on","sets":[]}]}
        """.data(using: .utf8)!

        let result = try Json.decode(from: json, to: EvaluationsResult.self)

        XCTAssertNil(result.since)
        XCTAssertNil(result.till)
        XCTAssertEqual(result.evaluations.count, 1)
    }

    func testEvaluationsResultThrowsOnInvalidEvaluation() {
        let json = """
        {"evaluations":[{"featureName":"flag"}]}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: EvaluationsResult.self))
    }

    // MARK: - EventEntity (encoding)

    func testEventEntityEncodesAllFields() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        let event = EventEntity(trafficType: "user", eventType: "purchase", value: 12.5, properties: ["plan": "pro"], timestamp: timestamp)

        let dict = event.toJsonObject() as! [String: Any]

        XCTAssertEqual(dict["eventTypeId"] as? String, "purchase")
        XCTAssertEqual(dict["trafficTypeName"] as? String, "user")
        XCTAssertEqual(dict["value"] as? Double, 12.5)
        XCTAssertEqual(dict["timestamp"] as? Int64, 1_000_000)
        XCTAssertEqual(dict["properties"] as? [String: String], ["plan": "pro"])
    }

    func testEventEntityOmitsNilValueAndProperties() throws {
        let event = EventEntity(trafficType: "user", eventType: "click")

        let dict = event.toJsonObject() as! [String: Any]

        XCTAssertNil(dict["value"])
        XCTAssertNil(dict["properties"])
    }
}
