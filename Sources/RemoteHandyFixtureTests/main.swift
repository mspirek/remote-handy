import Foundation
import RemoteHandyCore
import SQLite3

@main
struct RemoteHandyFixtureTests {
    static func main() async {
        do {
            try await runAll()
            print("fixture tests passed")
        } catch {
            fputs("fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runAll() async throws {
        try testInstanceLockExcludesSecondOwnerAndRecovers()
        try testSettingsNormalizeInvalidTiming()
        try await testWatcherCancellation()
        try testHandyPasteFilterOnlyConsumesMatchingSyntheticPairs()
        try testHandySQLiteBehavior()
        try testHandySourceSurvivesSettingsRoundTrip()
        try await testWatcherReturnsExistingNewRow()
        try await testWatcherWaitsForStableTranscriptRow()
        try await testWatcherRetriesTemporaryDatabaseLock()
        try await testWatcherTimesOutWithoutNewRow()
        try testDefaultSettingsKeepRiskyFeaturesOff()
        try testFnShortcutSettings()
        try testSettingsRoundTrip()
        try testSettingsStoreCreatesAndUpgradesSettings()
        try testClipboardTextFormatterAppendsTrailingSpace()
    }

    private static func testInstanceLockExcludesSecondOwnerAndRecovers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("instance.lock")
        let first = SingleInstanceLock(), second = SingleInstanceLock()
        try expectEqual(try first.acquire(at: path), true)
        try expectEqual(try second.acquire(at: path), false)
        first.release()
        try expectEqual(try second.acquire(at: path), true)
        second.release()
    }

    private static func testSettingsNormalizeInvalidTiming() throws {
        let settings = AppSettings(hotkeyMinimumHoldSeconds: -1, waitTimeoutSeconds: .infinity, pollIntervalSeconds: .nan).normalizedForCurrentVersion()
        try expectEqual(settings.hotkeyMinimumHoldSeconds, 0.1)
        try expectEqual(settings.waitTimeoutSeconds, 120)
        try expectEqual(settings.pollIntervalSeconds, 0.25)
    }

    private static func testWatcherCancellation() async throws {
        let task = Task {
            let watcher = TranscriptWatcher(store: MemoryTranscriptStore(rows: []))
            return try await watcher.waitForNext(after: 0, timeoutSeconds: 60)
        }
        task.cancel()
        do { _ = try await task.value; throw TestFailure("cancelled watcher must not complete") }
        catch is CancellationError {}
    }

    private static func testHandyPasteFilterOnlyConsumesMatchingSyntheticPairs() throws {
        var filter = HandyPasteFilter()
        try expectEqual(filter.shouldSuppress(kind: .down, key: 9, command: true, sourcePID: 0, handyPID: 42, targetMatches: true), false)
        try expectEqual(filter.shouldSuppress(kind: .down, key: 9, command: true, sourcePID: 99, handyPID: 42, targetMatches: true), false)
        try expectEqual(filter.shouldSuppress(kind: .down, key: 9, command: true, sourcePID: 42, handyPID: nil, targetMatches: true), false)
        try expectEqual(filter.shouldSuppress(kind: .down, key: 9, command: true, sourcePID: 42, handyPID: 42, targetMatches: false), false)
        try expectEqual(filter.shouldSuppress(kind: .down, key: 51, command: false, sourcePID: 42, handyPID: 42, targetMatches: true), false)
        try expectEqual(filter.shouldSuppress(kind: .modifiers, key: 55, command: true, sourcePID: 42, handyPID: 42, targetMatches: true), true)
        try expectEqual(filter.shouldSuppress(kind: .down, key: 9, command: true, sourcePID: 42, handyPID: 42, targetMatches: true), true)
        try expectEqual(filter.isComplete, false)
        try expectEqual(filter.shouldSuppress(kind: .up, key: 9, command: true, sourcePID: 42, handyPID: 42, targetMatches: false), true)
        try expectEqual(filter.isComplete, false)
        try expectEqual(filter.shouldSuppress(kind: .modifiers, key: 55, command: false, sourcePID: 42, handyPID: 42, targetMatches: false), true)
        try expectEqual(filter.isComplete, true)
        try expectEqual(filter.suppressedPasteCount, 1)
    }

    private static func testHandySQLiteBehavior() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.db")
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let db = handle else {
            throw TestFailure("Could not create Handy fixture")
        }
        defer { sqlite3_close(db) }
        func execute(_ sql: String) throws {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw TestFailure("Handy fixture SQL failed")
            }
        }
        try execute("""
        CREATE TABLE transcription_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT, file_name TEXT NOT NULL,
          timestamp INTEGER NOT NULL, saved BOOLEAN NOT NULL DEFAULT 0,
          title TEXT NOT NULL, transcription_text TEXT NOT NULL,
          post_processed_text TEXT, post_process_prompt TEXT,
          post_process_requested BOOLEAN NOT NULL DEFAULT 0);
        INSERT INTO transcription_history (file_name,timestamp,title,transcription_text,post_processed_text)
        VALUES ('fixture.wav',1,'test','  ',NULL),
               ('fixture.wav',2,'test','raw','  Final processed text  '),
               ('fixture.wav',3,'test','  raw fallback  ','  '),
               ('fixture.wav',4,'test','Unicode café 👋',NULL);
        """)
        let before = try Data(contentsOf: url)
        let store = HandySQLiteTranscriptStore(databasePath: url.path)
        try expectEqual(try store.maxRowID(), 4)
        try expectEqual(try store.oldestUsableRow(after: 0)?.text, "Final processed text")
        try expectEqual(try store.oldestUsableRow(after: 2)?.text, "raw fallback")
        try expectEqual(try store.oldestUsableRow(after: 3)?.text, "Unicode café 👋")
        try expectEqual(try store.oldestUsableRow(after: 4), nil)
        try expectEqual(try Data(contentsOf: url), before)
        try execute("BEGIN EXCLUSIVE;")
        do {
            _ = try store.oldestUsableRow(after: 0)
            throw TestFailure("Expected a retryable lock error")
        } catch TranscriptStoreError.temporarilyUnavailable {}
        try execute("ROLLBACK;")
        try expectEqual(try store.oldestUsableRow(after: 3)?.text, "Unicode café 👋")
        try execute("DELETE FROM transcription_history;")
        try expectEqual(try store.maxRowID(), 0)
        try execute("INSERT INTO transcription_history(file_name,timestamp,title,transcription_text) VALUES ('fixture.wav',5,'test','after pruning');")
        try expectEqual(try store.oldestUsableRow(after: 4)?.rowID, 5)
        try expectEqual(try store.oldestUsableRow(after: 4)?.text, "after pruning")
        // More than 25 blank entries must not hide a usable row.
        for _ in 0..<30 {
            try execute("INSERT INTO transcription_history(file_name,timestamp,title,transcription_text) VALUES ('fixture.wav',6,'test','');")
        }
        try execute("INSERT INTO transcription_history(file_name,timestamp,title,transcription_text) VALUES ('fixture.wav',7,'test','after blanks');")
        try expectEqual(try store.oldestUsableRow(after: 5)?.text, "after blanks")
        let missing = directory.appendingPathComponent("missing.db")
        do {
            _ = try HandySQLiteTranscriptStore(databasePath: missing.path).maxRowID()
            throw TestFailure("Read-only Handy store should reject a missing database")
        } catch is TranscriptSQLiteError {}
        try expectEqual(FileManager.default.fileExists(atPath: missing.path), false)
        try execute("DROP TABLE transcription_history;")
        do {
            _ = try store.maxRowID()
            throw TestFailure("Handy store must report an incompatible schema")
        } catch is TranscriptSQLiteError {}
    }

    private static func testHandySourceSurvivesSettingsRoundTrip() throws {
        let input = Data(#"{"handyDatabasePath":"/tmp/custom-handy.db"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: input)
        let output = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        try expectEqual(output["handyDatabasePath"] as? String, "/tmp/custom-handy.db")
    }

    private static func testWatcherReturnsExistingNewRow() async throws {
        let store = MemoryTranscriptStore(rows: [
            TranscriptRow(rowID: 20, text: "before"),
            TranscriptRow(rowID: 21, text: "after")
        ])
        let watcher = TranscriptWatcher(store: store, pollIntervalSeconds: 0.05, stabilizationSeconds: 0)

        let row = try await watcher.waitForNext(after: 20, timeoutSeconds: 1)

        try expectEqual(row, TranscriptRow(rowID: 21, text: "after"))
    }

    private static func testWatcherWaitsForStableTranscriptRow() async throws {
        let finalRow = TranscriptRow(rowID: 21, text: "complete transcript", status: "raw_transcript")
        let store = SequencedTranscriptStore(rowsByCall: [
            TranscriptRow(rowID: 21, text: "com", status: "raw_transcript"),
            TranscriptRow(rowID: 21, text: "com", status: "raw_transcript"),
            finalRow,
            finalRow,
            finalRow
        ])
        let watcher = TranscriptWatcher(store: store, pollIntervalSeconds: 0.05, stabilizationSeconds: 0.08)

        let row = try await watcher.waitForNext(after: 20, timeoutSeconds: 1)

        try expectEqual(row, finalRow)
    }

    private static func testWatcherRetriesTemporaryDatabaseLock() async throws {
        let store = BusyThenReadyStore()
        let watcher = TranscriptWatcher(store: store, pollIntervalSeconds: 0.05, stabilizationSeconds: 0)
        let row = try await watcher.waitForNext(after: 1, timeoutSeconds: 1)
        try expectEqual(row.text, "after temporary lock")
    }

    private static func testWatcherTimesOutWithoutNewRow() async throws {
        let store = MemoryTranscriptStore(rows: [
            TranscriptRow(rowID: 20, text: "before")
        ])
        let watcher = TranscriptWatcher(store: store, pollIntervalSeconds: 0.05, stabilizationSeconds: 0)

        do {
            _ = try await watcher.waitForNext(after: 20, timeoutSeconds: 0.1)
            throw TestFailure("Expected timeout")
        } catch let error as TranscriptWatcherError {
            try expectEqual(error, .timeout(afterRowID: 20))
        }
    }

    private static func testDefaultSettingsKeepRiskyFeaturesOff() throws {
        let settings = AppSettings()

        try expectEqual(settings.settingsSchemaVersion, AppSettings.currentSchemaVersion)
        try expectEqual(settings.donorAppPath, AppSettings.defaultDonorAppPath)
        try expectEqual(settings.hiddenDonorEnabled, true)
        try expectEqual(settings.automaticPasteEnabled, false)
        try expectEqual(settings.automaticTriggerEnabled, false)
        try expectEqual(settings.hotkeyModifiers, [.function])
        try expectEqual(settings.hotkeyMinimumHoldSeconds, 0.2)
        try expectEqual(settings.waitTimeoutSeconds, 60)
    }

    private static func testFnShortcutSettings() throws {
        let data = Data(#"{"hotkeyModifiers":["function"]}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        try expectEqual(HotkeyModifier.displayName(for: settings.hotkeyModifiers), "Fn")
        let normalized = settings.normalizedForCurrentVersion()
        let roundTrip = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(normalized))
        try expectEqual(roundTrip.hotkeyModifiers, settings.hotkeyModifiers)
    }

    private static func testSettingsRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-handy-settings-\(UUID().uuidString)", isDirectory: true)
        let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let settings = AppSettings(
            settingsSchemaVersion: AppSettings.currentSchemaVersion,
            handyDatabasePath: "/tmp/history.db",
            donorAppPath: "/tmp/Remote Handy Copy Donor.app",
            hiddenDonorEnabled: false,
            automaticPasteEnabled: true,
            automaticTriggerEnabled: false,
            hotkeyModifiers: [.control, .option, .shift],
            hotkeyMinimumHoldSeconds: 0.4,
            waitTimeoutSeconds: 30,
            pollIntervalSeconds: 0.5
        )

        try store.save(settings)

        try expectEqual(try store.load(), settings)
    }

    private static func testSettingsStoreCreatesAndUpgradesSettings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-handy-settings-\(UUID().uuidString)", isDirectory: true)
        let settingsURL = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: settingsURL)
        let defaultSettings = AppSettings(donorAppPath: "/tmp/Remote Handy Copy Donor.app")

        let created = try store.loadOrCreate(defaultSettings: defaultSettings)
        try expectEqual(created, defaultSettings)
        try expectTrue(
            FileManager.default.fileExists(atPath: settingsURL.path),
            "settings file should be created"
        )

        let oldSettingsJSON = """
        {
          "donorAppPath": "",
          "waitTimeoutSeconds": 30
        }
        """
        guard let oldSettingsData = oldSettingsJSON.data(using: .utf8) else {
            throw TestFailure("could not encode old settings fixture")
        }
        try oldSettingsData.write(to: settingsURL, options: .atomic)

        let upgraded = try store.loadOrCreate(defaultSettings: defaultSettings)
        try expectEqual(upgraded.settingsSchemaVersion, AppSettings.currentSchemaVersion)
        try expectEqual(upgraded.donorAppPath, "/tmp/Remote Handy Copy Donor.app")
        try expectEqual(upgraded.hotkeyModifiers, [.function])
        try expectEqual(upgraded.waitTimeoutSeconds, 30)
    }

    private static func testClipboardTextFormatterAppendsTrailingSpace() throws {
        try expectEqual(
            ClipboardTextFormatter.appendTrailingSpace("Hello world."),
            "Hello world. "
        )
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
        if actual != expected {
            throw TestFailure("Expected \(expected), got \(actual)")
        }
    }

    private static func expectTrue(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw TestFailure(message)
        }
    }
}

private final class SequencedTranscriptStore: TranscriptStore {
    private let rowsByCall: [TranscriptRow?]
    private var callCount = 0

    init(rowsByCall: [TranscriptRow?]) {
        self.rowsByCall = rowsByCall
    }

    func maxRowID() throws -> Int64 {
        rowsByCall.compactMap(\.?.rowID).max() ?? 0
    }

    func oldestUsableRow(after rowID: Int64) throws -> TranscriptRow? {
        defer { callCount += 1 }

        let row = rowsByCall[min(callCount, rowsByCall.count - 1)]
        guard let row,
              row.rowID > rowID,
              !row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return row
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private final class BusyThenReadyStore: TranscriptStore {
    private var blocked = true
    func maxRowID() throws -> Int64 { 2 }
    func oldestUsableRow(after rowID: Int64) throws -> TranscriptRow? {
        if blocked {
            blocked = false
            throw TranscriptStoreError.temporarilyUnavailable
        }
        return TranscriptRow(rowID: 2, text: "after temporary lock")
    }
}
