import Foundation

public enum HotkeyModifier: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case control
    case option
    case shift
    case command
    case function

    public static let defaultShortcut: [HotkeyModifier] = [.function]

    public var displayName: String {
        switch self {
        case .control:
            "Control"
        case .option:
            "Option"
        case .shift:
            "Shift"
        case .command:
            "Command"
        case .function:
            "Fn"
        }
    }

    public static func displayName(for modifiers: [HotkeyModifier]) -> String {
        ordered(modifiers).map(\.displayName).joined(separator: "+")
    }

    public static func ordered(_ modifiers: [HotkeyModifier]) -> [HotkeyModifier] {
        Self.allCases.filter { modifiers.contains($0) }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let defaultDonorAppPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/Remote Handy Copy Donor.app")
        .path

    public var settingsSchemaVersion: Int
    public var handyDatabasePath: String
    public var handyPostProcessShortcutEnabled: Bool
    public var donorAppPath: String
    public var hiddenDonorEnabled: Bool
    public var automaticPasteEnabled: Bool
    public var automaticTriggerEnabled: Bool
    public var hotkeyModifiers: [HotkeyModifier]
    public var hotkeyMinimumHoldSeconds: Double
    public var waitTimeoutSeconds: Double
    public var pollIntervalSeconds: Double

    private enum CodingKeys: String, CodingKey {
        case settingsSchemaVersion
        case handyDatabasePath, handyPostProcessShortcutEnabled
        case donorAppPath
        case hiddenDonorEnabled
        case automaticPasteEnabled
        case automaticTriggerEnabled
        case hotkeyModifiers
        case hotkeyMinimumHoldSeconds
        case waitTimeoutSeconds
        case pollIntervalSeconds
    }

    public init(
        settingsSchemaVersion: Int = AppSettings.currentSchemaVersion,
        handyDatabasePath: String = HandySQLiteTranscriptStore.defaultDatabasePath,
        handyPostProcessShortcutEnabled: Bool = false,
        donorAppPath: String = AppSettings.defaultDonorAppPath,
        hiddenDonorEnabled: Bool = true,
        automaticPasteEnabled: Bool = false,
        automaticTriggerEnabled: Bool = false,
        hotkeyModifiers: [HotkeyModifier] = HotkeyModifier.defaultShortcut,
        hotkeyMinimumHoldSeconds: Double = 0.2,
        waitTimeoutSeconds: Double = 60,
        pollIntervalSeconds: Double = 0.25
    ) {
        self.handyPostProcessShortcutEnabled = handyPostProcessShortcutEnabled
        self.handyDatabasePath = handyDatabasePath
        self.settingsSchemaVersion = settingsSchemaVersion
        self.donorAppPath = donorAppPath
        self.hiddenDonorEnabled = hiddenDonorEnabled
        self.automaticPasteEnabled = automaticPasteEnabled
        self.automaticTriggerEnabled = automaticTriggerEnabled
        self.hotkeyModifiers = HotkeyModifier.ordered(hotkeyModifiers)
        self.hotkeyMinimumHoldSeconds = hotkeyMinimumHoldSeconds
        self.waitTimeoutSeconds = waitTimeoutSeconds
        self.pollIntervalSeconds = pollIntervalSeconds
    }

    public init(from decoder: Decoder) throws {
        let defaults = AppSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.handyPostProcessShortcutEnabled = try container.decodeIfPresent(Bool.self, forKey: .handyPostProcessShortcutEnabled) ?? false
        self.handyDatabasePath = try container.decodeIfPresent(String.self, forKey: .handyDatabasePath) ?? defaults.handyDatabasePath
        self.settingsSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .settingsSchemaVersion)
            ?? defaults.settingsSchemaVersion
        self.donorAppPath = try container.decodeIfPresent(String.self, forKey: .donorAppPath)
            ?? defaults.donorAppPath
        self.hiddenDonorEnabled = try container.decodeIfPresent(Bool.self, forKey: .hiddenDonorEnabled)
            ?? defaults.hiddenDonorEnabled
        self.automaticPasteEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticPasteEnabled)
            ?? defaults.automaticPasteEnabled
        self.automaticTriggerEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticTriggerEnabled)
            ?? defaults.automaticTriggerEnabled
        self.hotkeyModifiers = try container.decodeIfPresent([HotkeyModifier].self, forKey: .hotkeyModifiers)
            ?? defaults.hotkeyModifiers
        self.hotkeyMinimumHoldSeconds = try container.decodeIfPresent(Double.self, forKey: .hotkeyMinimumHoldSeconds)
            ?? defaults.hotkeyMinimumHoldSeconds
        self.waitTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .waitTimeoutSeconds)
            ?? defaults.waitTimeoutSeconds
        self.pollIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .pollIntervalSeconds)
            ?? defaults.pollIntervalSeconds
    }

    public func makeTranscriptStore() -> any TranscriptStore {
        HandySQLiteTranscriptStore(databasePath: handyDatabasePath)
    }

    public func normalizedForCurrentVersion(defaultSettings: AppSettings = AppSettings()) -> AppSettings {
        var settings = self
        settings.settingsSchemaVersion = Self.currentSchemaVersion

        if settings.donorAppPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.donorAppPath = defaultSettings.donorAppPath
        }
        settings.hotkeyModifiers = HotkeyModifier.ordered(settings.hotkeyModifiers)
        if settings.hotkeyModifiers.isEmpty {
            settings.hotkeyModifiers = defaultSettings.hotkeyModifiers
        }

        func bounded(_ value: Double, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        settings.pollIntervalSeconds = bounded(settings.pollIntervalSeconds, 0.25, 0.05...5)
        settings.waitTimeoutSeconds = bounded(settings.waitTimeoutSeconds, 120, 5...120)
        settings.hotkeyMinimumHoldSeconds = bounded(settings.hotkeyMinimumHoldSeconds, 0.2, 0.1...5)
        return settings
    }
}

public final class SettingsStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppSettings()
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(AppSettings.self, from: data)
    }

    public func loadOrCreate(defaultSettings: AppSettings = AppSettings()) throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let settings = defaultSettings.normalizedForCurrentVersion(defaultSettings: defaultSettings)
            try save(settings)
            return settings
        }

        let data = try Data(contentsOf: fileURL)
        let loaded = try decoder.decode(AppSettings.self, from: data)
        let normalized = loaded.normalizedForCurrentVersion(defaultSettings: defaultSettings)
        try save(normalized)
        return normalized
    }

    public func save(_ settings: AppSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}
