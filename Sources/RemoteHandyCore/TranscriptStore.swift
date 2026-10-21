import Foundation

public enum TranscriptStoreError: Error, Equatable {
    case temporarilyUnavailable
}

public protocol TranscriptStore {
    func maxRowID() throws -> Int64
    func oldestUsableRow(after rowID: Int64) throws -> TranscriptRow?
}

public final class MemoryTranscriptStore: TranscriptStore {
    private let rows: [TranscriptRow]

    public init(rows: [TranscriptRow]) {
        self.rows = rows.sorted { $0.rowID < $1.rowID }
    }

    public func maxRowID() throws -> Int64 {
        rows.map(\.rowID).max() ?? 0
    }

    public func oldestUsableRow(after rowID: Int64) throws -> TranscriptRow? {
        rows.first { row in
            row.rowID > rowID && !row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
