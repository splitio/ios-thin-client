import Foundation

enum ThinNotificationType: Equatable {
    case evaluationUpdate
    case control
    case occupancy
    case error
}

enum ControlType: String, Decodable {
    case streamingPaused = "STREAMING_PAUSED"
    case streamingResumed = "STREAMING_RESUMED"
    case streamingDisabled = "STREAMING_DISABLED"
    case streamingReset = "STREAMING_RESET"
    case unknown
}

class ThinNotification {
    let type: ThinNotificationType
    let channel: String?
    let timestamp: Int64

    init(type: ThinNotificationType, channel: String?, timestamp: Int64) {
        self.type = type
        self.channel = channel
        self.timestamp = timestamp
    }
}

enum NotificationDataType: Int {
    case flagUpdate = 0
    case rbsUpdate = 1
    case sUpdate = 2
    case lsUpdate = 3
}

enum UpdateStrategy: Int {
    case fetchAll = 0
    case boundedFetchRequest = 1
    case keyList = 2
}

class EvaluationUpdateNotification: ThinNotification {
    let changeNumber: Int64
    let dataType: NotificationDataType?
    let updateStrategy: UpdateStrategy?
    let algorithmSeed: Int?
    let hashingAlgorithm: Int?
    let updateIntervalMs: Int64?

    init(channel: String?, timestamp: Int64, changeNumber: Int64,
         dataType: NotificationDataType? = nil, updateStrategy: UpdateStrategy? = nil,
         algorithmSeed: Int? = nil, hashingAlgorithm: Int? = nil, updateIntervalMs: Int64? = nil) {
        self.changeNumber = changeNumber
        self.dataType = dataType
        self.updateStrategy = updateStrategy
        self.algorithmSeed = algorithmSeed
        self.hashingAlgorithm = hashingAlgorithm
        self.updateIntervalMs = updateIntervalMs
        super.init(type: .evaluationUpdate, channel: channel, timestamp: timestamp)
    }
}

class ThinControlNotification: ThinNotification {
    let controlType: ControlType

    init(channel: String?, timestamp: Int64, controlType: ControlType) {
        self.controlType = controlType
        super.init(type: .control, channel: channel, timestamp: timestamp)
    }
}

class ThinOccupancyNotification: ThinNotification {
    let publishers: Int

    init(channel: String?, timestamp: Int64, publishers: Int) {
        self.publishers = publishers
        super.init(type: .occupancy, channel: channel, timestamp: timestamp)
    }
}

class ThinStreamingError: ThinNotification {
    let message: String
    let code: Int
    let statusCode: Int?

    var isRetryable: Bool {
        return statusCode != 401
    }

    init(channel: String?, timestamp: Int64, message: String, code: Int, statusCode: Int?) {
        self.message = message
        self.code = code
        self.statusCode = statusCode
        super.init(type: .error, channel: channel, timestamp: timestamp)
    }
}
