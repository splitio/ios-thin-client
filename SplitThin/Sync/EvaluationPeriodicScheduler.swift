import Foundation
import Logging

protocol EvaluationPeriodicScheduler: Sendable {
    func start()
    func stop()
}

final class DefaultEvaluationPeriodicScheduler: EvaluationPeriodicScheduler, @unchecked Sendable {

    private let fetchCoordinator: EvaluationFetchCoordinator
    private let observer: Observer // For SDK events & logging
    private let target: Target
    private let filters: EvaluationFilters?
    private let intervalSeconds: Int

    private var task: Task<Void, Never>?
    private var isRunning = false
    private let lock = NSLock()

    init(fetchCoordinator: EvaluationFetchCoordinator, observer: Observer, target: Target, filters: EvaluationFilters?, intervalSeconds: Int) {
        self.fetchCoordinator = fetchCoordinator
        self.observer = observer
        self.target = target
        self.filters = filters
        self.intervalSeconds = intervalSeconds
    }

    func start() {
        withLock(lock) {
            guard !isRunning else { return }
            isRunning = true
        }

        task = Task { [weak self] in
            guard let self = self else {
                Logger.d("EvaluationPeriodicScheduler: self was deallocated, exiting")
                return
            }

            while !Task.isCancelled {
                let shouldRun = withLock(self.lock) { self.isRunning }
                guard shouldRun else {
                    Logger.d("EvaluationPeriodicScheduler: isRunning=false, exiting loop")
                    break
                }

                do {
                    Logger.d("EvaluationPeriodicScheduler: Sleeping for \(self.intervalSeconds)s")
                    try await Task.sleep(nanoseconds: UInt64(self.intervalSeconds) * 1_000_000_000)
                } catch {
                    Logger.d("EvaluationPeriodicScheduler: Sleep cancelled, exiting")
                    break
                }

                self.observer.notify(event: .pollTriggered(rate: self.intervalSeconds))

                do {
                    let evaluations = try await self.fetchCoordinator.fetchIfNeeded(target: self.target, filters: self.filters, reason: .periodic)
                    if !evaluations.isEmpty {
                        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: evaluations.map { $0.flag })
                        try? self.observer.notify(event: .evaluationsUpdated(metadata))
                    }
                } catch {
                    Logger.e("EvaluationPeriodicScheduler: Fetch failed: \(error)")
                }
            }
        }

        Logger.d("EvaluationPeriodicScheduler: Started with interval \(intervalSeconds)s")
    }

    func stop() {
        withLock(lock) {
            isRunning = false
        }
        task?.cancel()
        task = nil

        Logger.d("EvaluationPeriodicScheduler: Stopped")
    }
}
