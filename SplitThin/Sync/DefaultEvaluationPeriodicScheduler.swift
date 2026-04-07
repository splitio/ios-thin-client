import Foundation
import Logging

protocol EvaluationPeriodicScheduler: Sendable {
    func start()
    func stop()
}

final class DefaultEvaluationPeriodicScheduler: EvaluationPeriodicScheduler, @unchecked Sendable {

    private let evaluationProvider: EvaluationProvider
    private let evaluationRepository: EvaluationRepository
    private let target: Target
    private let filters: EvaluationFilters?
    private let intervalSeconds: Int

    private var task: Task<Void, Never>?
    private var isRunning = false
    private let lock = NSLock()

    init(evaluationProvider: EvaluationProvider, evaluationRepository: EvaluationRepository, target: Target, filters: EvaluationFilters?, intervalSeconds: Int) {
        self.evaluationProvider = evaluationProvider
        self.evaluationRepository = evaluationRepository
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

                if let change = await self.evaluationProvider.fetch(target: self.target, filters: self.filters) {
                    self.evaluationRepository.update(change.evaluations)
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
