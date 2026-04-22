import Foundation

typealias RetryPoliciesByCategory = [RequestCategory: CategoryRetryPolicies]

enum RequestCategory: Sendable {
    case auth
    case evaluations
    case events
    case telemetry

    var toHttpCategory: HttpCategory {
        switch self {
            case .auth: return .auth
            case .evaluations: return .evaluations
            case .events: return .events
            case .telemetry: return .telemetry
        }
    }
}

struct RetryPolicy: Sendable {
    enum BackoffStrategy: Sendable {
        case exponential
    }

    public let maxAttempts: Int
    public let backoffBaseSeconds: TimeInterval
    public let backoffStrategy: BackoffStrategy

    init(maxAttempts: Int = -1, backoffBaseSeconds: TimeInterval = 1.0, backoffStrategy: BackoffStrategy = .exponential) {
        self.maxAttempts = maxAttempts
        self.backoffBaseSeconds = backoffBaseSeconds
        self.backoffStrategy = backoffStrategy
    }

    static let `default` = RetryPolicy()
}

struct CategoryRetryPolicies: Sendable {
    let fallback: RetryPolicy?
    let byStatus: [Int: RetryPolicy?]

    init(fallback: RetryPolicy? = .default, byStatus: [Int: RetryPolicy?] = [:]) {
        self.fallback = fallback
        self.byStatus = byStatus
    }

    func policy(for statusCode: Int) -> RetryPolicy? {
        if byStatus.keys.contains(statusCode) {
            return byStatus[statusCode] ?? nil
        }
        return fallback
    }
}
