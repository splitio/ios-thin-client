import XCTest
@testable import SplitThin

final class EvaluationFetchCoordinatorEventsTest: XCTestCase {

    private var provider: EvaluationProviderMock!
    private var coordinator: DefaultEvaluationFetchCoordinator!
    private var observerSpy: ObserverSpy!

    private let target = Target(matchingKey: "user1", trafficType: "user")
    private let filters = EvaluationFilters(flagNames: ["flag1"])

    override func setUp() {
        super.setUp()
        provider = EvaluationProviderMock()
        observerSpy = ObserverSpy()
        coordinator = DefaultEvaluationFetchCoordinator(provider: provider, observer: observerSpy)
    }

    override func tearDown() {
        coordinator = nil
        provider = nil
        observerSpy = nil
        super.tearDown()
    }

    func testSuccessfulFetchEmitsExpectedEvents() async throws {
        provider.resultToReturn = EvaluationsResult(evaluations: [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])], till: 100)

        _ = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)

        let names = observerSpy.eventNames
        XCTAssertEqual(names[0], "evalFetchRequested")
        XCTAssertEqual(names[1], "evalFetchStarted")
        XCTAssertEqual(names[2], "evalFetchSucceeded")
        waitUntil(timeout: 2) { self.observerSpy.eventNames.contains("evalStorageUpdated") } // evalStorageUpdated is emitted from a Task
    }

    func testFailedFetchEmitsRequestedStartedAndFailed() async {
        provider.resultToReturn = nil

        _ = try? await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        let names = observerSpy.eventNames
        XCTAssertEqual(names[0], "evalFetchRequested")
        XCTAssertEqual(names[1], "evalFetchStarted")
        XCTAssertEqual(names[2], "evalFetchFailed")
    }

    func testDeduplicatedFetchEmitsDeduped() async throws {
        provider.resultToReturn = EvaluationsResult(evaluations: [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])], till: 1)
        provider.fetchDelay = 200_000_000

        async let fetch1: FetchResult = coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        try await Task.sleep(nanoseconds: 50_000_000)
        async let fetch2: FetchResult = coordinator.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        _ = try await (fetch1, fetch2)

        XCTAssertTrue(observerSpy.eventNames.contains("evalFetchDeduped"))
    }
}
