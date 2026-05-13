//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol TelemetrySubmitter: Sendable {
    func flush(count: Int?) async
}

final class DefaultTelemetrySubmitter: TelemetrySubmitter, @unchecked Sendable {

    private let storage: TelemetryReadStorage & TelemetryWriteStorage
    private let secureHttpClient: SecureHttpClient
    private let activeSessionId: String

    private var isSubmitting = false
    private let lock = NSLock()

    init(storage: TelemetryReadStorage & TelemetryWriteStorage, secureHttpClient: SecureHttpClient, activeSessionId: String) {
        self.storage = storage
        self.secureHttpClient = secureHttpClient
        self.activeSessionId = activeSessionId
    }

    func flush(count: Int?) async {
        let shouldRun = withLock(lock) {
            guard !isSubmitting else { return false }
            isSubmitting = true
            return true
        }

        guard shouldRun else {
            Logger.d("DefaultTelemetrySubmitter: Submission already in progress, dropping flush")
            return
        }

        defer {
            withLock(lock) { isSubmitting = false }
        }

        let records = await storage.getNonActive(activeSessionId: activeSessionId)
        guard !records.isEmpty else { return }

        let toSend = count.map { Array(records.prefix($0)) } ?? records

        do {
            let metricsArray = toSend.map { $0.metrics.toJsonObject() }
            let payload = try JSONSerialization.data(withJSONObject: metricsArray)
            _ = try await secureHttpClient.postTelemetry(payload: payload)
            await storage.remove(sessionIds: toSend.map { $0.sessionId })
        } catch {
            Logger.e("DefaultTelemetrySubmitter: Failed to submit telemetry: \(error)")
        }
    }
}
