//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

struct SessionMetricsDTO: DynamicCodable, Sendable {
    let sessionId: String
    var config: ConfigMetrics
    var runtime: RuntimeMetrics
    let platform: PlatformMetrics

    init(sessionId: String, config: ConfigMetrics, runtime: RuntimeMetrics, platform: PlatformMetrics) {
        self.sessionId = sessionId
        self.config = config
        self.runtime = runtime
        self.platform = platform
    }

    init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any] else {
            throw JsonError.invalidData
        }
        guard let sessionId = dict["sessionId"] as? String,
              let configObj = dict["config"],
              let runtimeObj = dict["runtime"],
              let platformObj = dict["platform"] else {
            throw JsonError.parsingFailed
        }
        self.sessionId = sessionId
        self.config = try ConfigMetrics(jsonObject: configObj)
        self.runtime = try RuntimeMetrics(jsonObject: runtimeObj)
        self.platform = try PlatformMetrics(jsonObject: platformObj)
    }

    func toJsonObject() -> Any {
        var dict = [String: Any]()
        dict["sessionId"] = sessionId
        dict["config"] = config.toJsonObject()
        dict["runtime"] = runtime.toJsonObject()
        dict["platform"] = platform.toJsonObject()
        return dict
    }
}

extension SessionMetricsDTO {
    struct ConfigMetrics: DynamicCodable, Sendable {
        let syncMode: String
        let pushRate: Int
        let evaluationRefreshRate: Int

        init(syncMode: String, pushRate: Int, evaluationRefreshRate: Int) {
            self.syncMode = syncMode
            self.pushRate = pushRate
            self.evaluationRefreshRate = evaluationRefreshRate
        }

        init(jsonObject: Any) throws {
            guard let dict = jsonObject as? [String: Any] else {
                throw JsonError.invalidData
            }
            guard let syncMode = dict["syncMode"] as? String,
                  let pushRate = dict["pushRate"] as? Int,
                  let evaluationRefreshRate = dict["evaluationRefreshRate"] as? Int else {
                throw JsonError.parsingFailed
            }
            self.syncMode = syncMode
            self.pushRate = pushRate
            self.evaluationRefreshRate = evaluationRefreshRate
        }

        func toJsonObject() -> Any {
            var dict = [String: Any]()
            dict["syncMode"] = syncMode
            dict["pushRate"] = pushRate
            dict["evaluationRefreshRate"] = evaluationRefreshRate
            return dict
        }
    }

    struct RuntimeMetrics: DynamicCodable, Sendable {
        var lastEvaluationsSync: Int64?
        var successfulJwtFetches: Int
        var evaluationCount: Int

        init(lastEvaluationsSync: Int64? = nil, successfulJwtFetches: Int = 0, evaluationCount: Int = 0) {
            self.lastEvaluationsSync = lastEvaluationsSync
            self.successfulJwtFetches = successfulJwtFetches
            self.evaluationCount = evaluationCount
        }

        init(jsonObject: Any) throws {
            guard let dict = jsonObject as? [String: Any] else {
                throw JsonError.invalidData
            }
            guard let successfulJwtFetches = dict["successfulJwtFetches"] as? Int,
                  let evaluationCount = dict["evaluationCount"] as? Int else {
                throw JsonError.parsingFailed
            }
            self.lastEvaluationsSync = dict["lastEvaluationsSync"] as? Int64
            self.successfulJwtFetches = successfulJwtFetches
            self.evaluationCount = evaluationCount
        }

        func toJsonObject() -> Any {
            var dict = [String: Any]()
            if let lastEvaluationsSync {
                dict["lastEvaluationsSync"] = lastEvaluationsSync
            }
            dict["successfulJwtFetches"] = successfulJwtFetches
            dict["evaluationCount"] = evaluationCount
            return dict
        }
    }

    struct PlatformMetrics: DynamicCodable, Sendable {
        let name: String
        let version: String

        init(name: String = "ios-thin", version: String = Version.semantic) {
            self.name = name
            self.version = version
        }

        init(jsonObject: Any) throws {
            guard let dict = jsonObject as? [String: Any] else {
                throw JsonError.invalidData
            }
            guard let name = dict["name"] as? String,
                  let version = dict["version"] as? String else {
                throw JsonError.parsingFailed
            }
            self.name = name
            self.version = version
        }

        func toJsonObject() -> Any {
            var dict = [String: Any]()
            dict["name"] = name
            dict["version"] = version
            return dict
        }
    }
}
