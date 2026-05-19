//  Created by Gaston Thea
//  Copyright © 2026 Harness. All rights reserved

import Foundation

struct RawThinNotification {
    let channel: String
    let data: String
    let timestamp: Int64
}

struct RawThinNotificationDto: DynamicDecodable {
    let channel: String?
    let data: String?
    let timestamp: Int64?
    let encoding: String?
    let id: String?
    let clientId: String?

    init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any] else { throw JsonError.parsingFailed }
        channel = dict["channel"] as? String
        data = dict["data"] as? String
        timestamp = dict["timestamp"] as? Int64
        encoding = dict["encoding"] as? String
        id = dict["id"] as? String
        clientId = dict["clientId"] as? String
    }
}

struct EvaluationUpdateDataDto: DynamicDecodable {
    let type: String?
    let changeNumber: Int64
    let dt: Int?
    let u: Int?
    let c: Int?
    let s: Int?
    let h: Int?
    let i: Int64?
    let d: String?

    init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any] else { throw JsonError.parsingFailed }
        guard let changeNumber = dict["changeNumber"] as? Int64 else { throw JsonError.parsingFailed }
        self.type = dict["type"] as? String
        self.changeNumber = changeNumber
        self.dt = dict["dt"] as? Int
        self.u = dict["u"] as? Int
        self.c = dict["c"] as? Int
        self.s = dict["s"] as? Int
        self.h = dict["h"] as? Int
        self.i = dict["i"] as? Int64
        self.d = dict["d"] as? String
    }
}

struct ControlDataDto: DynamicDecodable {
    let type: String?
    let controlType: String

    init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any],
              let controlType = dict["controlType"] as? String else { throw JsonError.parsingFailed }
        self.type = dict["type"] as? String
        self.controlType = controlType
    }
}

struct OccupancyDataDto: DynamicDecodable {
    let publishers: Int

    init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any],
              let metrics = dict["metrics"] as? [String: Any],
              let publishers = metrics["publishers"] as? Int else { throw JsonError.parsingFailed }
        self.publishers = publishers
    }
}

struct ErrorDataDto: DynamicDecodable {
    let type: String?
    let message: String
    let code: Int
    let statusCode: Int?

    init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any],
              let message = dict["message"] as? String,
              let code = dict["code"] as? Int else { throw JsonError.parsingFailed }
        self.type = dict["type"] as? String
        self.message = message
        self.code = code
        self.statusCode = dict["statusCode"] as? Int
    }
}

// MARK: - Parsing helpers

enum ThinNotificationDtoParser {
    static func parseRaw(jsonString: String) -> RawThinNotification? {
        guard let data = jsonString.data(using: .utf8),
              let dto = try? Json.decode(from: data, to: RawThinNotificationDto.self) else {
            return nil
        }
        return RawThinNotification(
            channel: dto.channel ?? "", data: dto.data ?? "",
            timestamp: dto.timestamp ?? 0)
    }

    static func parseEvaluationUpdate(jsonString: String) -> EvaluationUpdateDataDto? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? Json.decode(from: data, to: EvaluationUpdateDataDto.self)
    }

    static func parseControl(jsonString: String) -> ControlDataDto? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? Json.decode(from: data, to: ControlDataDto.self)
    }

    static func parseOccupancy(jsonString: String) -> OccupancyDataDto? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? Json.decode(from: data, to: OccupancyDataDto.self)
    }

    static func parseError(jsonString: String) -> ErrorDataDto? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? Json.decode(from: data, to: ErrorDataDto.self)
    }
}
