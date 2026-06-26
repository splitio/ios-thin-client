//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol EvaluationPeriodicScheduler: Sendable {
    func start()
    func stop()
    func setTarget(_ target: Target)
}

final class DefaultEvaluationPeriodicScheduler: EvaluationPeriodicScheduler, @unchecked Sendable {

    private let fetchCoordinator: EvaluationFetchCoordinator
    private let evaluationRepository: EvaluationRepository
    private let observer: Observer // For SDK events & logging
    private var target: Target
    private let filters: EvaluationFilters?
    private let intervalSeconds: Int

    private var task: Task<Void, Never>?
    private var isRunning = false
    private let lock = NSLock()

    init(fetchCoordinator: EvaluationFetchCoordinator, evaluationRepository: EvaluationRepository, observer: Observer, target: Target, filters: EvaluationFilters?, intervalSeconds: Int) {
        self.fetchCoordinator = fetchCoordinator
        self.evaluationRepository = evaluationRepository
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

                // Read the current target each cycle so a setTarget mid-flight is picked up on the next poll.
                let currentTarget = withLock(self.lock) { self.target }
                self.observer.notify(event: .pollTriggered(rate: self.intervalSeconds))

                do {
                    let result = try await self.fetchCoordinator.fetchIfNeeded(target: currentTarget, filters: self.filters, reason: .periodic)
                    let changedFlags = self.evaluationRepository.applyFetched(result, for: currentTarget)
                    if !changedFlags.isEmpty {
                        self.observer.notify(event: .evaluationsUpdated(SdkUpdateMetadata(type: .flagsUpdate, names: changedFlags, changeNumber: result.changeNumber)))
                    }
                } catch {
                    Logger.e("EvaluationPeriodicScheduler: Fetch failed")
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

    func setTarget(_ target: Target) {
        withLock(lock) { self.target = target }
    }

    // TODO: cancel task on deInit()
}
