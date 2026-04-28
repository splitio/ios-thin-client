//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

protocol DynamicDecodable {
    init(jsonObject: Any) throws
}

protocol DynamicEncodable {
    func toJsonObject() -> Any
}

typealias DynamicCodable = DynamicDecodable & DynamicEncodable

enum JsonError: Error {
    case parsingFailed
    case invalidData
}

// Our custom equivalent of Codable (less safe.. but faster). 
// The safety issue is completely mitigated with unit testing.
enum Json {
    static func decode<T: DynamicDecodable>(from data: Data, to type: T.Type) throws -> T {
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        return try T.init(jsonObject: jsonObject)
    }

    static func decodeArray<T: DynamicDecodable>(from data: Data, to type: T.Type) throws -> [T] {
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let array = jsonObject as? [Any] else {
            throw JsonError.invalidData
        }
        return try array.map { try T.init(jsonObject: $0) }
    }

    static func encode<T: DynamicEncodable>(_ value: T) throws -> Data {
        let jsonObject = value.toJsonObject()
        return try JSONSerialization.data(withJSONObject: jsonObject, options: [])
    }
}
