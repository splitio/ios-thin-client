import XCTest
import Http
@testable import SplitThin

final class DefaultSecureHttpClientTest: XCTestCase {

    private var retryableHttpMock: RetryableHttpClientMock!
    private var authProviderMock: AuthProviderMock!
    private var serviceEndpoints: ServiceEndpoints!
    private var client: DefaultSecureHttpClient!

    override func setUp() {
        super.setUp()
        retryableHttpMock = RetryableHttpClientMock()
        authProviderMock = AuthProviderMock()
        authProviderMock.credentialToReturn = makeCredential()
        serviceEndpoints = ServiceEndpoints.builder().set(sdkEndpoint: "https://evaluator.split.io").set(eventsEndpoint: "https://events.split.io").set(telemetryServiceEndpoint: "https://telemetry.split.io").build()
        client = DefaultSecureHttpClient(retryableHttpClient: retryableHttpMock, authProvider: authProviderMock, serviceEndpoints: serviceEndpoints, apiKey: "test-api-key")
    }

    // MARK: - fetchEvaluations

    func testFetchEvaluationsUsesAuthToken() async throws {
        authProviderMock.credentialToReturn = makeCredential(token: "jwt-token")
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", trafficType: "user")

        try await client.fetchEvaluations(target: target)

        XCTAssertEqual(authProviderMock.getCredentialCallCount, 1)

        let endpoint = retryableHttpMock.executeCalls[0].endpoint
        XCTAssertEqual(endpoint.headers["Authorization"], "Bearer jwt-token")
    }

    func testFetchEvaluationsUrlContainsOnlySinceQueryParam() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "lucrap", trafficType: "user")

        try await client.fetchEvaluations(target: target)

        let url = retryableHttpMock.executeCalls[0].endpoint.url.absoluteString
        XCTAssertTrue(url.contains("since=-1"), "URL should contain since param: \(url)")
        XCTAssertFalse(url.contains("key="), "key should be in body, not URL: \(url)")
        XCTAssertFalse(url.contains("capabilities="), "capabilities should not be in URL anymore: \(url)")
        XCTAssertFalse(url.contains("sets="), "sets should be in body, not URL: \(url)")
        XCTAssertFalse(url.contains("names="), "names should not be sent at all: \(url)")
    }

    func testFetchEvaluationsBodyIncludesKey() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "lucrap", trafficType: "user")

        try await client.fetchEvaluations(target: target)

        let body = try parseBody(retryableHttpMock.executeCalls[0].body)
        XCTAssertEqual(body["key"] as? String, "lucrap")
    }

    func testFetchEvaluationsBodyIncludesBucketingKeyWhenSet() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", bucketingKey: "bucket-42", trafficType: "user")

        try await client.fetchEvaluations(target: target)

        let body = try parseBody(retryableHttpMock.executeCalls[0].body)
        XCTAssertEqual(body["bucketingKey"] as? String, "bucket-42")
    }

    func testFetchEvaluationsBodyIncludesNullBucketingKeyWhenNil() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", trafficType: "user")

        try await client.fetchEvaluations(target: target)

        let body = try parseBody(retryableHttpMock.executeCalls[0].body)
        XCTAssertTrue(body["bucketingKey"] is NSNull, "bucketingKey must always be present (null when unset) for digest parity")
    }

    func testFetchEvaluationsBodyIncludesFlagSetsAsArray() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", trafficType: "user")
        let filters = EvaluationFilters(flagSets: ["setB", "setA"])

        try await client.fetchEvaluations(target: target, filters: filters)

        let body = try parseBody(retryableHttpMock.executeCalls[0].body)
        XCTAssertEqual(body["sets"] as? [String], ["setA", "setB"], "sets should be sorted")
    }

    func testFetchEvaluationsBodyIncludesEmptyFlagSetsWhenEmpty() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", trafficType: "user")

        try await client.fetchEvaluations(target: target, filters: EvaluationFilters(flagSets: []))

        let body = try parseBody(retryableHttpMock.executeCalls[0].body)
        XCTAssertEqual(body["sets"] as? [String], [], "sets must always be present (empty array when unset) for digest parity")
    }

    func testFetchEvaluationsBodyExcludesNamesEvenWhenProvided() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", trafficType: "user")
        let filters = EvaluationFilters(flagNames: ["flag1", "flag2"])

        try await client.fetchEvaluations(target: target, filters: filters)

        let body = try parseBody(retryableHttpMock.executeCalls[0].body)
        XCTAssertNil(body["names"], "names is not supported in the body yet")
    }

    func testFetchEvaluationsBodyIncludesEmptyAttributesWhenNoneProvided() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", trafficType: "user")

        try await client.fetchEvaluations(target: target)

        let body = try parseBody(retryableHttpMock.executeCalls[0].body)
        XCTAssertEqual((body["attributes"] as? [String: Any])?.isEmpty, true, "attributes must always be present (empty object when unset) for digest parity")
    }

    func testFetchEvaluationsBodyKeysAreAlphabeticallySorted() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]
        let configsClient = DefaultSecureHttpClient(retryableHttpClient: retryableHttpMock, authProvider: authProviderMock, serviceEndpoints: serviceEndpoints, configsEnabled: true, apiKey: "test-api-key")

        let target = Target(matchingKey: "user1", bucketingKey: "bk-1", attributes: ["zebra": "z", "alpha": "a"], trafficType: "user")
        let filters = EvaluationFilters(flagSets: ["setA"])

        try await configsClient.fetchEvaluations(target: target, filters: filters)

        let bodyString = String(data: retryableHttpMock.executeCalls[0].body!, encoding: .utf8)!

        // Top-level keys must appear in alphabetical order: attributes < bucketingKey < configs < key < sets
        let attributesIdx = bodyString.range(of: "\"attributes\"")!.lowerBound
        let bucketingKeyIdx = bodyString.range(of: "\"bucketingKey\"")!.lowerBound
        let configsIdx = bodyString.range(of: "\"configs\"")!.lowerBound
        let keyIdx = bodyString.range(of: "\"key\"")!.lowerBound
        let setsIdx = bodyString.range(of: "\"sets\"")!.lowerBound
        XCTAssertTrue(attributesIdx < bucketingKeyIdx, "attributes should come before bucketingKey: \(bodyString)")
        XCTAssertTrue(bucketingKeyIdx < configsIdx, "bucketingKey should come before configs: \(bodyString)")
        XCTAssertTrue(configsIdx < keyIdx, "configs should come before key: \(bodyString)")
        XCTAssertTrue(keyIdx < setsIdx, "key should come before sets: \(bodyString)")

        // Nested attribute keys also sorted: alpha < zebra
        let alphaIdx = bodyString.range(of: "\"alpha\"")!.lowerBound
        let zebraIdx = bodyString.range(of: "\"zebra\"")!.lowerBound
        XCTAssertTrue(alphaIdx < zebraIdx, "nested attribute keys should also be sorted: \(bodyString)")
    }

    func testFetchEvaluationsBodyIncludesAttributesWhenProvided() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", attributes: ["plan": "enterprise", "role": "admin"], trafficType: "user")

        try await client.fetchEvaluations(target: target)

        let body = try parseBody(retryableHttpMock.executeCalls[0].body)
        let attributes = body["attributes"] as? [String: String]
        XCTAssertEqual(attributes?["plan"], "enterprise")
        XCTAssertEqual(attributes?["role"], "admin")
    }

    func testFetchEvaluationsBodyIncludesAttributesListOrderedString() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", attributes: ["plan": ["lola", "pepe", "abacio"], "role": "admin"], trafficType: "user")

        try await client.fetchEvaluations(target: target)

        let body = try parseBody(retryableHttpMock.executeCalls[0].body)
        let attributes = body["attributes"] as? [String: Any]
        XCTAssertEqual(attributes?["plan"] as? [String], ["abacio", "lola", "pepe"], "sets should be sorted")
    }
    
    func testFetchEvaluationsBodyIncludesAttributesListOrderedNumber() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", attributes: ["plan": [2, 1.5, 0], "role": "admin"], trafficType: "user")

        try await client.fetchEvaluations(target: target)

        let body = try parseBody(retryableHttpMock.executeCalls[0].body)
        let attributes = body["attributes"] as? [String: Any]
        XCTAssertEqual(attributes?["plan"] as? [Double], [0, 1.5, 2], "sets should be sorted")
    }
    
    func testFetchEvaluationsBodyIncludesAttributesListOrderedBool() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", attributes: ["plan": [true, false], "role": "admin"], trafficType: "user")

        try await client.fetchEvaluations(target: target)

        let body = try parseBody(retryableHttpMock.executeCalls[0].body)
        let attributes = body["attributes"] as? [String: Any]
        XCTAssertEqual(attributes?["plan"] as? [Bool], [false, true], "sets should be sorted")
    }

    func testFetchEvaluationsIncludesContentDigestHeader() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "Mauro", attributes: ["city": "mdp", "age": 150], trafficType: "user")

        try await client.fetchEvaluations(target: target)

        let endpoint = retryableHttpMock.executeCalls[0].endpoint
        XCTAssertEqual(endpoint.headers["X-Harness-FME-Content-Digest"], "T05eBmW0qdw")
    }

    func testFetchEvaluationsUsesEvaluationsCategory() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", trafficType: "user")

        try await client.fetchEvaluations(target: target)

        XCTAssertEqual(retryableHttpMock.executeCalls[0].category, .evaluations)
    }

    // MARK: - Configs enabled

    func testBodyIncludesConfigsTrueWhenEnabled() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]
        let configsClient = DefaultSecureHttpClient(retryableHttpClient: retryableHttpMock, authProvider: authProviderMock, serviceEndpoints: serviceEndpoints, configsEnabled: true, apiKey: "test-api-key")

        let target = Target(matchingKey: "user1", trafficType: "user")

        try await configsClient.fetchEvaluations(target: target)

        let body = try parseBody(retryableHttpMock.executeCalls[0].body)
        XCTAssertEqual(body["configs"] as? Bool, true)
    }

    func testBodyIncludesConfigsFalseWhenDisabled() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", trafficType: "user")

        try await client.fetchEvaluations(target: target)

        let body = try parseBody(retryableHttpMock.executeCalls[0].body)
        XCTAssertEqual(body["configs"] as? Bool, false)
    }

    // MARK: - 401 Retry Flow

    func testFetchEvaluationsRetriesOn401() async throws {
        authProviderMock.credentialToReturn = makeCredential(token: "stale-token")

        retryableHttpMock.responses = [
            HttpResponse(code: 401, data: nil),
            HttpResponse(code: 200, data: Data())
        ]

        let target = Target(matchingKey: "user1", trafficType: "user")

        try await client.fetchEvaluations(target: target)

        XCTAssertEqual(authProviderMock.invalidateCallCount, 1)
        XCTAssertEqual(authProviderMock.lastTargetInvalidated, "user1")
        XCTAssertEqual(authProviderMock.getCredentialCallCount, 2)
        XCTAssertEqual(retryableHttpMock.executeCalls.count, 2)
    }

    func testFetchEvaluationsReturns401OnSecondFailure() async throws {
        authProviderMock.credentialToReturn = makeCredential(token: "bad-token")

        retryableHttpMock.responses = [
            HttpResponse(code: 401, data: nil),
            HttpResponse(code: 401, data: nil)
        ]

        let target = Target(matchingKey: "user1", trafficType: "user")

        let response = try await client.fetchEvaluations(target: target)

        XCTAssertEqual(response.code, 401)
        XCTAssertEqual(retryableHttpMock.executeCalls.count, 2)
    }

    func testFetchEvaluationsDoesNotRetryOnNon401Error() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 500, data: nil)]

        let target = Target(matchingKey: "user1", trafficType: "user")

        let response = try await client.fetchEvaluations(target: target)

        XCTAssertEqual(response.code, 500)
        XCTAssertEqual(authProviderMock.invalidateCallCount, 0)
        XCTAssertEqual(retryableHttpMock.executeCalls.count, 1)
    }

    // MARK: - postEvents & postTelemetry

    func testPostEventsUsesEventsCategory() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 202, data: nil)]

        let payload = "{}".data(using: .utf8)!

        let response = try await client.postEvents(payload: payload)

        XCTAssertEqual(response.code, 202)
        XCTAssertEqual(retryableHttpMock.executeCalls[0].category, .events)
        XCTAssertEqual(retryableHttpMock.executeCalls[0].body, payload)
    }

    func testPostTelemetryUsesTelemetryCategory() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: nil)]

        let payload = "{}".data(using: .utf8)!

        let response = try await client.postTelemetry(payload: payload)

        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(retryableHttpMock.executeCalls[0].category, .telemetry)
    }

    // MARK: - contentDigest

    func testContentDigestEmptyJsonObject() {
        let digest = DefaultSecureHttpClient.contentDigest(for: Data("{}".utf8))

        XCTAssertEqual(digest, "J8dGcK23UHU")
    }

    func testContentDigestFullEvaluationsBody() {
        let body = Data(#"{"attributes":{"age":200,"colors":["green","red"],"country":"arg","version":"3.0.0"},"bucketingKey":123,"configs":true,"key":"mauro","sets":["set_a","set_b"]}"#.utf8)

        let digest = DefaultSecureHttpClient.contentDigest(for: body)

        XCTAssertEqual(digest, "UiiSm/lWBfs")
    }

    func testContentDigestIsDeterministic() {
        let body = Data(#"{"configs":false,"key":"user1"}"#.utf8)

        XCTAssertEqual(DefaultSecureHttpClient.contentDigest(for: body), DefaultSecureHttpClient.contentDigest(for: body))
    }

    func testContentDigestDifferentInputsProduceDifferentDigests() {
        let bodyA = Data(#"{"configs":false,"key":"alice"}"#.utf8)
        let bodyB = Data(#"{"configs":false,"key":"bob"}"#.utf8)

        XCTAssertNotEqual(DefaultSecureHttpClient.contentDigest(for: bodyA), DefaultSecureHttpClient.contentDigest(for: bodyB))
    }

    func testContentDigestHasNoBase64Padding() {
        let digest = DefaultSecureHttpClient.contentDigest(for: Data("{}".utf8))

        XCTAssertFalse(digest.contains("="), "digest should be base64 without padding: \(digest)")
    }

    // MARK: - Helpers
    private func makeCredential(token: String = "test-token") -> JwtCredential {
        JwtCredential(token: token, expiresAt: Date().addingTimeInterval(3600), pushEnabled: true)
    }

    private func parseBody(_ data: Data?) throws -> [String: Any] {
        guard let data, let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Body could not be parsed as JSON object")
            return [:]
        }
        return parsed
    }
}
