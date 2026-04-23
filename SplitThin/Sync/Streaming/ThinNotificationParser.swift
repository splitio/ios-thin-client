import Foundation

private let kOccupancyPrefix = "[?occupancy=metrics.publishers]"
private let kEvaluationUpdateType = "EVALUATIONS_UPDATE"
private let kControlType = "CONTROL"
private let kErrorType = "ERROR"

protocol ThinNotificationParser {
    func parseRaw(jsonString: String) -> RawThinNotification?
    func parse(raw: RawThinNotification) -> ThinNotification?
}

final class DefaultThinNotificationParser: ThinNotificationParser {

    func parseRaw(jsonString: String) -> RawThinNotification? {
        ThinNotificationDtoParser.parseRaw(jsonString: jsonString)
    }

    func parse(raw: RawThinNotification) -> ThinNotification? {
        // raw.data is a JSON envelope with channel, timestamp, and a nested "data" string
        guard let outerData = raw.data.data(using: .utf8),
              let outerDto = try? Json.decode(from: outerData, to: RawThinNotificationDto.self),
              let data = outerDto.data, !data.isEmpty else {
            return nil
        }

        let channel = outerDto.channel ?? raw.channel
        let timestamp = outerDto.timestamp ?? raw.timestamp

        if channel.contains(kOccupancyPrefix) {
            guard let dto = ThinNotificationDtoParser.parseOccupancy(jsonString: data) else { return nil }
            return ThinOccupancyNotification(channel: channel, timestamp: timestamp, publishers: dto.publishers)
        }

        if data.contains(kEvaluationUpdateType) {
            guard let dto = ThinNotificationDtoParser.parseEvaluationUpdate(jsonString: data) else { return nil }
            return EvaluationUpdateNotification(
                channel: channel, timestamp: timestamp, changeNumber: dto.changeNumber,
                dataType: dto.dt.flatMap(NotificationDataType.init),
                updateStrategy: dto.u.flatMap(UpdateStrategy.init),
                algorithmSeed: dto.s, hashingAlgorithm: dto.h, updateIntervalMs: dto.i)
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
