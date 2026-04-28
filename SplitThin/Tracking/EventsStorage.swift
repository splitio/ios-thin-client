//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

protocol EventsReadStorage: Sendable {
    func getBatch(size: Int) async -> [EventEntity]
    func count() async -> Int
}

protocol EventsWriteStorage: Sendable {
    func add(_ event: EventEntity) async
    func remove(_ events: [EventEntity]) async
    func clear() async
}

final class DefaultEventsStorage: EventsReadStorage, EventsWriteStorage, Sendable {

    private let storage: CoreDataStorage

    init(storage: CoreDataStorage) {
        self.storage = storage
    }

    // MARK: - EventsWriteStorage

    func add(_ event: EventEntity) async {
        let propertiesJson = encodeProperties(event.properties)
        try? await storage.addEvent(id: event.id, trafficType: event.trafficType, eventType: event.eventType, value: event.value, properties: propertiesJson, timestamp: event.timestamp.timeIntervalSince1970)
    }

    func remove(_ events: [EventEntity]) async {
        let ids = events.map { $0.id.uuidString }
        await storage.removeEvents(ids: ids)
    }

    func clear() async {
        await storage.clearEvents()
    }

    // MARK: - EventsReadStorage

    func getBatch(size: Int) async -> [EventEntity] {
        let batch = await storage.getEventBatch(size: size)
        return batch.map { item in
            EventEntity(id: item.id, trafficType: item.trafficType, eventType: item.eventType, value: item.value, properties: decodeProperties(item.properties), timestamp: Date(timeIntervalSince1970: item.timestamp))
        }
    }

    func count() async -> Int {
        await storage.countEvents()
    }

    // MARK: - Private

    private func encodeProperties(_ properties: [String: String]?) -> String? {
        guard let properties, !properties.isEmpty else { return nil }
        
        guard let data = try? JSONSerialization.data(withJSONObject: properties),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    private func decodeProperties(_ json: String?) -> [String: String]? {
        guard let json, let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        return dict
    }
}
