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
        let dto = EventDTO(id: event.id, trafficType: event.trafficType, eventType: event.eventType, value: event.value, properties: encodeProperties(event.properties), timestamp: event.timestamp.timeIntervalSince1970)
        try? await storage.addEvent(dto)
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
        return batch.map { dto in
            EventEntity(id: dto.id, trafficType: dto.trafficType, eventType: dto.eventType, value: dto.value, properties: decodeProperties(dto.properties), timestamp: Date(timeIntervalSince1970: dto.timestamp))
        }
    }

    func count() async -> Int {
        await storage.countEvents()
    }

    // MARK: - Private

    private func encodeProperties(_ properties: [String: Any]?) -> String? {
        guard let properties, !properties.isEmpty else { return nil }

        guard let data = try? JSONSerialization.data(withJSONObject: properties),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    private func decodeProperties(_ json: String?) -> [String: Any]? {
        guard let json, let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict
    }
}
