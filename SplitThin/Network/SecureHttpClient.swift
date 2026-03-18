import Foundation

enum SecureHttpError: Error {
    case invalidResponse
    case httpError(code: Int, message: String)
    case decodingError(Error)
    case networkError(Error)
}

protocol SecureHttpClient: Sendable {
    func get<T: DynamicDecodable>(url: URL, path: String?) async throws -> T
    func getArray<T: DynamicDecodable>(url: URL, path: String?) async throws -> [T]
    func post<T: DynamicDecodable>(url: URL, path: String?, body: Data?) async throws -> T
}
