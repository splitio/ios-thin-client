import Foundation

private let kOccupancyPrefix = "[?occupancy=metrics.publishers]"
private let kEvaluationUpdateType = "EVALUATION_UPDATE"
private let kControlType = "CONTROL"
private let kErrorType = "ERROR"

protocol ThinNotificationParser {
    func parseRaw(jsonString: String) -> RawThinNotification?
    func parse(raw: RawThinNotification) -> ThinNotification?
}

final class DefaultThinNotificationParser: ThinNotificationParser {

    func parseRaw(jsonString: String) -> RawThinNotification? {
        return ThinNotificationDtoParser.parseRaw(jsonString: jsonString)
    }

    func parse(raw: RawThinNotification) -> ThinNotification? {
        let channel = raw.channel
        let data = raw.data
        let timestamp = raw.timestamp

        if channel.contains(kOccupancyPrefix) {
            guard let dto = ThinNotificationDtoParser.parseOccupancy(jsonString: data) else { return nil }
            return ThinOccupancyNotification(channel: channel, timestamp: timestamp, publishers: dto.publishers)
        }

        if data.contains(kEvaluationUpdateType) {
            guard let dto = ThinNotificationDtoParser.parseEvaluationUpdate(jsonString: data) else { return nil }
            return EvaluationUpdateNotification(
                channel: channel, timestamp: timestamp, changeNumber: dto.changeNumber,
                updateIntervalMs: dto.i, algorithmSeed: dto.s, hashingAlgorithm: dto.h)
        }

        if data.contains(kControlType) {
            guard let dto = ThinNotificationDtoParser.parseControl(jsonString: data) else { return nil }
            let ct = ControlType(rawValue: dto.controlType) ?? .unknown
            return ThinControlNotification(channel: channel, timestamp: timestamp, controlType: ct)
        }

        if data.contains(kErrorType) {
            guard let dto = ThinNotificationDtoParser.parseError(jsonString: data) else { return nil }
            return ThinStreamingError(channel: channel, timestamp: timestamp,
                                      message: dto.message, code: dto.code, statusCode: dto.statusCode)
        }

        return nil
    }
}
