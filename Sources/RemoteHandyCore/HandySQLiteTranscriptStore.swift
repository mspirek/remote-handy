import Foundation
import SQLite3

public enum TranscriptSQLiteError: Error, Equatable, CustomStringConvertible {
    case openFailed(path: String, message: String)
    case prepareFailed(sql: String, message: String)
    case stepFailed(message: String)

    public var description: String {
        switch self {
        case let .openFailed(path, message):
            "Could not open SQLite database at \(path): \(message)"
        case let .prepareFailed(_, message):
            "Could not prepare SQLite query: \(message)"
        case let .stepFailed(message):
            "SQLite query failed: \(message)"
        }
    }
}

public final class HandySQLiteTranscriptStore: TranscriptStore {
    public static let defaultDatabasePath =
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/com.pais.handy/history.db"

    private let databasePath: String

    public init(databasePath: String = HandySQLiteTranscriptStore.defaultDatabasePath) {
        self.databasePath = databasePath
    }

    public func maxRowID() throws -> Int64 {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = "SELECT COALESCE(MAX(id), 0) FROM transcription_history;"
        let statement = try prepare(sql: sql, db: db)
        defer { sqlite3_finalize(statement) }

        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            throw queryError(db, code: result)
        }

        return sqlite3_column_int64(statement, 0)
    }

    public func oldestUsableRow(after rowID: Int64) throws -> TranscriptRow? {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, post_processed_text, transcription_text, timestamp
        FROM transcription_history
        WHERE id > ?
        ORDER BY id ASC;
        """

        let statement = try prepare(sql: sql, db: db)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, rowID)

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                throw queryError(db, code: result)
            }

            guard let text = bestTranscriptText(from: statement) else {
                continue
            }

            return TranscriptRow(
                rowID: sqlite3_column_int64(statement, 0),
                text: text,
                timestamp: stringColumn(statement, 3),
                status: "complete"
            )
        }
    }

    private func openDatabase() throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(databasePath, &db, flags, nil) == SQLITE_OK, let opened = db else {
            let message = db.map(errorMessage) ?? "unknown error"
            if let db {
                sqlite3_close(db)
            }
            throw TranscriptSQLiteError.openFailed(path: databasePath, message: message)
        }

        sqlite3_busy_timeout(opened, 100)
        return opened
    }

    private func prepare(sql: String, db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let prepared = statement else {
            if let statement { sqlite3_finalize(statement) }
            throw queryError(db, code: result)
        }

        return prepared
    }

    private func stringColumn(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index)
        else {
            return nil
        }

        return String(cString: cString)
    }

    private func bestTranscriptText(from statement: OpaquePointer) -> String? {
        // Handy saves history after post-processing; prefer its final nonblank text.
        for index in 1...2 {
            guard let value = stringColumn(statement, Int32(index)) else {
                continue
            }

            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private func queryError(_ db: OpaquePointer, code: Int32) -> Error {
        if code == SQLITE_BUSY || code == SQLITE_LOCKED {
            return TranscriptStoreError.temporarilyUnavailable
        }
        return TranscriptSQLiteError.stepFailed(message: errorMessage(db))
    }

    private func errorMessage(_ db: OpaquePointer) -> String {
        if let cString = sqlite3_errmsg(db) {
            return String(cString: cString)
        }
        return "unknown error"
    }
}
