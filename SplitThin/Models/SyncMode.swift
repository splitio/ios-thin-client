import Foundation

public enum SyncMode: String, Sendable {
    case streaming = "STREAMING"
    case polling = "POLLING"
    case singleSync = "SINGLE_SYNC"
}
