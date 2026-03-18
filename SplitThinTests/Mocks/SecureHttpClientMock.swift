import Foundation
@testable import SplitThin

final class SecureHttpClientMock: SecureHttpClient, @unchecked Sendable {

    var getResult: Any?
    var getArrayResult: [Any]?
    var postResult: Any?
    var errorToThrow: Error?

    func get<T: DynamicDecodable>(url: URL, path: String?) async throws -> T {
        if let error = errorToThrow {
            throw error
        }
        guard let result = getResult as? T else {
            throw SecureHttpError.invalidResponse
        }
        return result
    }

    func getArray<T: DynamicDecodable>(url: URL, path: String?) async throws -> [T] {
        if let error = errorToThrow {
            throw error
        }
        guard let result = getArrayResult as? [T] else {
            throw SecureHttpError.invalidResponse
        }
        return result
    }

    func post<T: DynamicDecodable>(url: URL, path: String?, body: Data?) async throws -> T {
        if let error = errorToThrow {
            throw error
        }
        guard let result = postResult as? T else {
            throw SecureHttpError.invalidResponse
        }
        return result
    }
}
