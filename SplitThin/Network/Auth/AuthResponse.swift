import Foundation

struct AuthResponse: DynamicDecodable {
    let token: String
    let pushEnabled: Bool
    let connDelay: Int?

    init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any] else {
            throw JsonError.invalidData
        }
        guard let token = dict["token"] as? String, let pushEnabled = dict["pushEnabled"] as? Bool else {
            throw JsonError.parsingFailed
        }
        self.token = token
        self.pushEnabled = pushEnabled
        self.connDelay = dict["connDelay"] as? Int
    }
}
