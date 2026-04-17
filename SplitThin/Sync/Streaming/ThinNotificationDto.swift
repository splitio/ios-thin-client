import Foundation

struct RawThinNotification {
    let channel: String
    let data: String
    let timestamp: Int64
}

private struct RawThinNotificationDto: Decodable {
    let channel: String
    let data: String
    let timestamp: Int64
}

struct EvaluationUpdateDataDto: Decodable {
    let type: String?
    let changeNumber: Int64
    let i: Int64?   // updateIntervalMs
    let s: Int?     // algorithmSeed
    let h: Int?     // hashingAlgorithm

    enum CodingKeys: String, CodingKey {
        case type, changeNumber, i, s, h
    }
}

struct ControlDataDto: Decodable {
    let type: String?
    let controlType: String
}

struct OccupancyMetrics: Decodable {
    let publishers: Int
}

struct OccupancyDataDto: Decodable {
    let metrics: OccupancyMetrics

    var publishers: Int { metrics.publishers }
}

struct ErrorDataDto: Decodable {
    let type: String?
    let message: String
    let code: Int
    let statusCode: Int?
}

// MARK: - Parsing helpers

enum ThinNotificationDtoParser {
    static func parseRaw(jsonString: String) -> RawThinNotification? {
        guard let data = jsonString.data(using: .utf8),
              let dto = try? JSONDecoder().decode(RawThinNotificationDto.self, from: data) else {
            return nil
        }
        return RawThinNotification(channel: dto.channel, data: dto.data, timestamp: dto.timestamp)
    }

    static func parseEvaluationUpdate(jsonString: String) -> EvaluationUpdateDataDto? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(EvaluationUpdateDataDto.self, from: data)
    }

    static func parseControl(jsonString: String) -> ControlDataDto? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ControlDataDto.self, from: data)
    }

    static func parseOccupancy(jsonString: String) -> OccupancyDataDto? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(OccupancyDataDto.self, from: data)
    }

    static func parseError(jsonString: String) -> ErrorDataDto? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ErrorDataDto.self, from: data)
    }
}
