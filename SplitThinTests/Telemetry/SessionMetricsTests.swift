import XCTest
@testable import SplitThin

final class SessionMetricsTests: XCTestCase {

    // MARK: - Round-trip

    func testRoundTripWithAllFields() throws {
        let metrics = SessionMetrics(
            sessionId: "abc-123",
            config: .init(syncMode: "streaming", pushRate: 60, evaluationRefreshRate: 300),
            runtime: .init(lastEvaluationsSync: 1_715_000_000_000, successfulJwtFetches: 5, evaluationCount: 42),
            platform: .init(name: "ios-thin", version: "0.1.0")
        )

        let data = try Json.encode(metrics)
        let decoded = try Json.decode(from: data, to: SessionMetrics.self)

        XCTAssertEqual(decoded.sessionId, "abc-123")
        XCTAssertEqual(decoded.config.syncMode, "streaming")
        XCTAssertEqual(decoded.config.pushRate, 60)
        XCTAssertEqual(decoded.config.evaluationRefreshRate, 300)
        XCTAssertEqual(decoded.runtime.lastEvaluationsSync, 1_715_000_000_000)
        XCTAssertEqual(decoded.runtime.successfulJwtFetches, 5)
        XCTAssertEqual(decoded.runtime.evaluationCount, 42)
        XCTAssertEqual(decoded.platform.name, "ios-thin")
        XCTAssertEqual(decoded.platform.version, "0.1.0")
    }

    func testRoundTripWithNilLastEvaluationsSync() throws {
        let metrics = SessionMetrics(
            sessionId: "def-456",
            config: .init(syncMode: "polling", pushRate: 30, evaluationRefreshRate: 120),
            runtime: .init(lastEvaluationsSync: nil, successfulJwtFetches: 0, evaluationCount: 0),
            platform: .init(name: "ios-thin", version: "0.1.0")
        )

        let data = try Json.encode(metrics)
        let decoded = try Json.decode(from: data, to: SessionMetrics.self)

        XCTAssertEqual(decoded.sessionId, "def-456")
        XCTAssertNil(decoded.runtime.lastEvaluationsSync)
        XCTAssertEqual(decoded.runtime.successfulJwtFetches, 0)
        XCTAssertEqual(decoded.runtime.evaluationCount, 0)
    }

    // MARK: - Decoding

    func testDecodesFromRawJson() throws {
        let json = """
        {
            "sessionId": "sess-1",
            "config": {"syncMode": "streaming", "pushRate": 60, "evaluationRefreshRate": 300},
            "runtime": {"successfulJwtFetches": 3, "evaluationCount": 10, "lastEvaluationsSync": 999},
            "platform": {"name": "ios-thin", "version": "0.1.0"}
        }
        """.data(using: .utf8)!

        let decoded = try Json.decode(from: json, to: SessionMetrics.self)

        XCTAssertEqual(decoded.sessionId, "sess-1")
        XCTAssertEqual(decoded.config.syncMode, "streaming")
        XCTAssertEqual(decoded.runtime.lastEvaluationsSync, 999)
        XCTAssertEqual(decoded.runtime.successfulJwtFetches, 3)
        XCTAssertEqual(decoded.runtime.evaluationCount, 10)
        XCTAssertEqual(decoded.platform.name, "ios-thin")
    }

    // MARK: - Error handling

    func testThrowsOnMissingSessionId() {
        let json = """
        {
            "config": {"syncMode": "streaming", "pushRate": 60, "evaluationRefreshRate": 300},
            "runtime": {"successfulJwtFetches": 0, "evaluationCount": 0},
            "platform": {"name": "ios-thin", "version": "0.1.0"}
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: SessionMetrics.self))
    }

    func testThrowsOnMissingConfig() {
        let json = """
        {
            "sessionId": "sess-1",
            "runtime": {"successfulJwtFetches": 0, "evaluationCount": 0},
            "platform": {"name": "ios-thin", "version": "0.1.0"}
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: SessionMetrics.self))
    }

    func testThrowsOnMissingRuntime() {
        let json = """
        {
            "sessionId": "sess-1",
            "config": {"syncMode": "streaming", "pushRate": 60, "evaluationRefreshRate": 300},
            "platform": {"name": "ios-thin", "version": "0.1.0"}
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: SessionMetrics.self))
    }

    func testThrowsOnMissingPlatform() {
        let json = """
        {
            "sessionId": "sess-1",
            "config": {"syncMode": "streaming", "pushRate": 60, "evaluationRefreshRate": 300},
            "runtime": {"successfulJwtFetches": 0, "evaluationCount": 0}
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: SessionMetrics.self))
    }

    func testThrowsOnInvalidJson() {
        let json = "not valid json".data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: SessionMetrics.self))
    }

    func testThrowsOnNonDictRoot() {
        let json = "[1,2,3]".data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: SessionMetrics.self))
    }

    // MARK: - Nested struct errors

    func testThrowsOnInvalidConfigFields() {
        let json = """
        {
            "sessionId": "sess-1",
            "config": {"syncMode": "streaming"},
            "runtime": {"successfulJwtFetches": 0, "evaluationCount": 0},
            "platform": {"name": "ios-thin", "version": "0.1.0"}
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: SessionMetrics.self))
    }

    func testThrowsOnInvalidRuntimeFields() {
        let json = """
        {
            "sessionId": "sess-1",
            "config": {"syncMode": "streaming", "pushRate": 60, "evaluationRefreshRate": 300},
            "runtime": {},
            "platform": {"name": "ios-thin", "version": "0.1.0"}
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: SessionMetrics.self))
    }

    func testThrowsOnInvalidPlatformFields() {
        let json = """
        {
            "sessionId": "sess-1",
            "config": {"syncMode": "streaming", "pushRate": 60, "evaluationRefreshRate": 300},
            "runtime": {"successfulJwtFetches": 0, "evaluationCount": 0},
            "platform": {"name": "ios-thin"}
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try Json.decode(from: json, to: SessionMetrics.self))
    }

    // MARK: - Encoding

    func testEncodeOmitsNilLastEvaluationsSync() throws {
        let metrics = SessionMetrics(
            sessionId: "sess-1",
            config: .init(syncMode: "streaming", pushRate: 60, evaluationRefreshRate: 300),
            runtime: .init(lastEvaluationsSync: nil, successfulJwtFetches: 0, evaluationCount: 0),
            platform: .init(name: "ios-thin", version: "0.1.0")
        )

        let dict = metrics.toJsonObject() as! [String: Any]
        let runtimeDict = dict["runtime"] as! [String: Any]

        XCTAssertNil(runtimeDict["lastEvaluationsSync"])
    }

    func testEncodeIncludesLastEvaluationsSyncWhenPresent() throws {
        let metrics = SessionMetrics(
            sessionId: "sess-1",
            config: .init(syncMode: "streaming", pushRate: 60, evaluationRefreshRate: 300),
            runtime: .init(lastEvaluationsSync: 12345, successfulJwtFetches: 1, evaluationCount: 2),
            platform: .init(name: "ios-thin", version: "0.1.0")
        )

        let dict = metrics.toJsonObject() as! [String: Any]
        let runtimeDict = dict["runtime"] as! [String: Any]

        XCTAssertEqual(runtimeDict["lastEvaluationsSync"] as? Int64, 12345)
    }

    // MARK: - PlatformMetrics defaults

    func testPlatformMetricsDefaultValues() {
        let platform = SessionMetrics.PlatformMetrics()

        XCTAssertEqual(platform.name, "ios-thin")
        XCTAssertEqual(platform.version, Version.semantic)
    }
}
