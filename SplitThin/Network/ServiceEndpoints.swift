import Foundation
import Logging

public final class ServiceEndpoints: Sendable {

    private static let defaultSdkEndpoint = "https://sdk.split.io/api"
    private static let defaultEventsEndpoint = "https://events.split.io/api"
    private static let defaultAuthServiceEndpoint = "https://auth.split.io/api/v2"
    private static let defaultStreamingEndpoint = "https://streaming.split.io/sse"
    private static let defaultTelemetryEndpoint = "https://telemetry.split.io/api/v1"

    public let sdkEndpoint: URL
    public let eventsEndpoint: URL
    public let authServiceEndpoint: URL
    public let streamingServiceEndpoint: URL
    public let telemetryServiceEndpoint: URL

    private let invalidEndpoints: [String]

    var allEndpointsValid: Bool {
        invalidEndpoints.isEmpty
    }

    var endpointsInvalidMessage: String? {
        guard !invalidEndpoints.isEmpty else { return nil }
        return invalidEndpoints.map { "Endpoint is invalid: \($0)" }.joined(separator: "\n")
    }

    private init(sdkEndpoint: URL, eventsEndpoint: URL, authServiceEndpoint: URL, streamingServiceEndpoint: URL, telemetryServiceEndpoint: URL, invalidEndpoints: [String]) {
        self.sdkEndpoint = sdkEndpoint
        self.eventsEndpoint = eventsEndpoint
        self.authServiceEndpoint = authServiceEndpoint
        self.streamingServiceEndpoint = streamingServiceEndpoint
        self.telemetryServiceEndpoint = telemetryServiceEndpoint
        self.invalidEndpoints = invalidEndpoints
    }

    public static func builder() -> Builder {
        Builder()
    }

    public final class Builder {

        private var sdkEndpoint = defaultSdkEndpoint
        private var eventsEndpoint = defaultEventsEndpoint
        private var authServiceEndpoint = defaultAuthServiceEndpoint
        private var streamingServiceEndpoint = defaultStreamingEndpoint
        private var telemetryServiceEndpoint = defaultTelemetryEndpoint

        @discardableResult
        public func set(sdkEndpoint: String) -> Self {
            self.sdkEndpoint = sdkEndpoint
            return self
        }

        @discardableResult
        public func set(eventsEndpoint: String) -> Self {
            self.eventsEndpoint = eventsEndpoint
            return self
        }

        @discardableResult
        public func set(authServiceEndpoint: String) -> Self {
            self.authServiceEndpoint = authServiceEndpoint
            return self
        }

        @discardableResult
        public func set(streamingServiceEndpoint: String) -> Self {
            self.streamingServiceEndpoint = streamingServiceEndpoint
            return self
        }

        @discardableResult
        public func set(telemetryServiceEndpoint: String) -> Self {
            self.telemetryServiceEndpoint = telemetryServiceEndpoint
            return self
        }

        public func build() -> ServiceEndpoints {
            var invalidEndpoints = [String]()

            let sdk = createUrl(string: sdkEndpoint, invalidEndpoints: &invalidEndpoints)
            let events = createUrl(string: eventsEndpoint, invalidEndpoints: &invalidEndpoints)
            let auth = createUrl(string: authServiceEndpoint, invalidEndpoints: &invalidEndpoints)
            let streaming = createUrl(string: streamingServiceEndpoint, invalidEndpoints: &invalidEndpoints)
            let telemetry = createUrl(string: telemetryServiceEndpoint, invalidEndpoints: &invalidEndpoints)

            return ServiceEndpoints(
                sdkEndpoint: sdk,
                eventsEndpoint: events,
                authServiceEndpoint: auth,
                streamingServiceEndpoint: streaming,
                telemetryServiceEndpoint: telemetry,
                invalidEndpoints: invalidEndpoints
            )
        }

        private func createUrl(string: String, invalidEndpoints: inout [String]) -> URL {
            if let url = URL(string: string), !string.isEmpty {
                return url
            }
            invalidEndpoints.append(string)
            return URL(string: "http://127.0.0.1")!
        }
    }
}
