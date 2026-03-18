import XCTest
import Http
@testable import SplitThin

final class SecureHttpClientTest: XCTestCase {

    func testFetchEvaluationsReturnsResponse() async throws {
        let mock = SecureHttpClientMock()
        let expectedData = "{\"flag\":\"test\"}".data(using: .utf8)!
        mock.fetchEvaluationsResult = HttpResponse(code: 200, data: expectedData)

        let target = Target(matchingKey: "user1")
        let filters = EvaluationFilters(flagNames: ["flag1"])

        let response = try await mock.fetchEvaluations(target: target, filters: filters)

        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(response.data, expectedData)
        XCTAssertEqual(mock.fetchEvaluationsCalls.count, 1)
        XCTAssertEqual(mock.fetchEvaluationsCalls.first?.target.matchingKey, "user1")
    }

    func testPostEventsReturnsResponse() async throws {
        let mock = SecureHttpClientMock()
        mock.postEventsResult = HttpResponse(code: 202, data: nil)

        let payload = "{}".data(using: .utf8)!
        let response = try await mock.postEvents(payload: payload)

        XCTAssertEqual(response.code, 202)
        XCTAssertEqual(mock.postEventsCalls.count, 1)
    }

    func testPostTelemetryReturnsResponse() async throws {
        let mock = SecureHttpClientMock()
        mock.postTelemetryResult = HttpResponse(code: 200, data: nil)

        let payload = "{}".data(using: .utf8)!
        let response = try await mock.postTelemetry(payload: payload)

        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(mock.postTelemetryCalls.count, 1)
    }

    func testThrowsErrorWhenConfigured() async {
        let mock = SecureHttpClientMock()
        mock.errorToThrow = SecureHttpError.httpError(code: 500, message: "Server error")

        let target = Target(matchingKey: "user1")

        do {
            _ = try await mock.fetchEvaluations(target: target, filters: nil)
            XCTFail("Expected error to be thrown")
        } catch let error as SecureHttpError {
            if case .httpError(let code, _) = error {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Expected httpError")
            }
        } catch {
            XCTFail("Unexpected error type")
        }
    }
}
