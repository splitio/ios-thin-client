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
        let shouldStart: Bool = withLock(lock) {
            guard !isRunning else { return false }
            isRunning = true
            return true
        }
        guard shouldStart else { return }


        let interval = intervalSeconds
        task = Task { [weak self] in
            while !Task.isCancelled {
                
                // Sleep WITHOUT holding `self`, so ARC can reclaim the scheduler if the owner
                // drops the client without calling stop().
                do {
                    Logger.d("EvaluationPeriodicScheduler: Sleeping for \(interval)s")
                    try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                } catch {
                    Logger.d("EvaluationPeriodicScheduler: Sleep cancelled, exiting")
                    break
                }

                // Re-acquire self for the fetch; bail if it was deallocated or stopped meanwhile.
                guard let self else { return }
                guard withLock(self.lock, { self.isRunning }) else {
                    Logger.d("EvaluationPeriodicScheduler: isRunning=false, exiting loop")
                    break
                }

                // Read the current target each cycle so a setTarget mid-flight is picked up on the next poll.
                let currentTarget = withLock(self.lock) { self.target }
                self.observer.notify(event: .pollTriggered(rate: interval))

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

    // Safety net: if the owner drops us without calling stop(), cancel the polling task.
    deinit {
        stop()
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
}
