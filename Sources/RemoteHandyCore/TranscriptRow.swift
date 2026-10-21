import Foundation

public struct TranscriptRow: Equatable, Sendable {
    public let rowID: Int64
    public let text: String
    public let timestamp: String?
    public let status: String?

    public init(rowID: Int64, text: String, timestamp: String? = nil, status: String? = nil) {
        self.rowID = rowID
        self.text = text
        self.timestamp = timestamp
        self.status = status
    }
}
