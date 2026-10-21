import Foundation
import RemoteHandyCore

struct AppDiagnostics {
    var status: String = "Idle"
    var isRunning: Bool = false
    var isManuallyDisabled: Bool = false
    var hotkeyEnabled: Bool = false
    var hotkeyMarkerRowID: Int64?
    var lastSkippedReason: String?
    var lastTriggerSource: String?
    var lastOperationStartedAt: Date?
    var lastMarkerRowID: Int64?
    var lastRowSeen: TranscriptRow?
    var lastCopiedRowID: Int64?
    var lastCopiedLength: Int?
    var lastDonorClipboardMatches: Bool?
    var lastDonorReadyAt: Date?
    var lastDonorHandoffWaitSeconds: Double?
    var lastDonorStillFrontmost: Bool?
    var lastAutoPasteEnabled: Bool?
    var lastAutoPasteResult: String?
    var lastAutoPasteAt: Date?
    var lastInputPermissionResult: String?
    var lastInputPermissionCheckAt: Date?
    var lastCodeSigningStatus: CodeSigningStatus?
    var lastDatabaseCheckAt: Date?
    var lastDatabaseMaxRowID: Int64?
    var lastBaselineHealthReport: BaselineHealthReport?
    var lastResetAt: Date?
    var lastError: String?
}

struct DiagnosticsSnapshot {
    let settings: AppSettings
    let diagnostics: AppDiagnostics
    let currentMaxRowID: Int64?
    let currentMaxRowError: String?
    let donorAppPath: String
    let logPath: String
    let appVersion: String
    let appBuild: String

    @MainActor func summary() -> String {
        var lines: [String] = []
        lines.append("Remote Handy Diagnostics")
        lines.append("Version: \(appVersion) (\(appBuild))")
        lines.append("Startup: \(StartupService.summary)")
        lines.append("Settings schema: \(settings.settingsSchemaVersion)")
        lines.append("")
        lines.append("Status: \(diagnostics.status)")
        lines.append("Running: \(diagnostics.isRunning ? "yes" : "no")")
        lines.append("Remote Handy manual disable: \(diagnostics.isManuallyDisabled ? "disabled" : "enabled")")
        lines.append("Dictation shortcut trigger: \(diagnostics.hotkeyEnabled ? "enabled" : "disabled")")
        lines.append("Dictation shortcut: \(HotkeyModifier.displayName(for: settings.hotkeyModifiers))")
        lines.append("Hotkey marker row: \(format(diagnostics.hotkeyMarkerRowID))")
        lines.append("Last skipped reason: \(diagnostics.lastSkippedReason ?? "none")")
        lines.append("")
        lines.append("Transcript source: Handy")
        lines.append("Handy Option+Shift+Space: \(settings.handyPostProcessShortcutEnabled ? "enabled" : "disabled")")
        lines.append("Transcript DB: \(settings.handyDatabasePath)")
        if let currentMaxRowID {
            lines.append("Current max row: \(currentMaxRowID)")
        } else {
            lines.append("Current max row: unavailable")
        }
        if let currentMaxRowError {
            lines.append("Current max row error: \(currentMaxRowError)")
        }
        lines.append("Last DB check: \(format(diagnostics.lastDatabaseCheckAt))")
        lines.append("Last DB max row: \(format(diagnostics.lastDatabaseMaxRowID))")
        lines.append("")
        if let report = diagnostics.lastBaselineHealthReport {
            lines.append(contentsOf: report.summaryLines())
        } else {
            lines.append("Baseline health: not checked")
        }
        lines.append("")
        lines.append("Last trigger source: \(diagnostics.lastTriggerSource ?? "none")")
        lines.append("Last operation started: \(format(diagnostics.lastOperationStartedAt))")
        lines.append("Last marker row: \(format(diagnostics.lastMarkerRowID))")
        if let row = diagnostics.lastRowSeen {
            lines.append("Last row seen: \(row.rowID)")
            lines.append("Last row status: \(row.status ?? "unknown")")
            lines.append("Last row timestamp: \(row.timestamp ?? "unknown")")
            lines.append("Last row text length: \(row.text.count)")
        } else {
            lines.append("Last row seen: none")
        }
        lines.append("")
        lines.append("Donor app: \(donorAppPath)")
        lines.append("Hidden donor: \(settings.hiddenDonorEnabled ? "yes" : "no")")
        lines.append("Last copied row: \(format(diagnostics.lastCopiedRowID))")
        lines.append("Last copied length: \(format(diagnostics.lastCopiedLength))")
        lines.append("Last donor ready: \(format(diagnostics.lastDonorReadyAt))")
        lines.append("Last donor clipboard match: \(format(diagnostics.lastDonorClipboardMatches))")
        lines.append("Last donor handoff wait seconds: \(format(diagnostics.lastDonorHandoffWaitSeconds))")
        lines.append("Last donor still frontmost: \(format(diagnostics.lastDonorStillFrontmost))")
        lines.append("")
        lines.append("")
        lines.append("Auto paste: \(settings.automaticPasteEnabled ? "enabled" : "disabled")")
        lines.append("Last auto paste enabled: \(format(diagnostics.lastAutoPasteEnabled))")
        lines.append("Last auto paste result: \(diagnostics.lastAutoPasteResult ?? "none")")
        lines.append("Last auto paste at: \(format(diagnostics.lastAutoPasteAt))")
        lines.append("Last input permission check: \(format(diagnostics.lastInputPermissionCheckAt))")
        lines.append("Last input permission result: \(diagnostics.lastInputPermissionResult ?? "none")")
        if let codeSigningStatus = diagnostics.lastCodeSigningStatus {
            lines.append("Code signing: \(codeSigningStatus.summary)")
            lines.append("Code signing requirement: \(codeSigningStatus.designatedRequirement ?? "none")")
            if !codeSigningStatus.verifyDetail.isEmpty {
                lines.append("Code signing verify detail: \(codeSigningStatus.verifyDetail)")
            }
        } else {
            lines.append("Code signing: not checked")
        }
        lines.append("")
        lines.append("Wait timeout seconds: \(settings.waitTimeoutSeconds)")
        lines.append("Poll interval seconds: \(settings.pollIntervalSeconds)")
        lines.append("Dictation shortcut min hold seconds: \(settings.hotkeyMinimumHoldSeconds)")
        lines.append("Log: \(logPath)")
        lines.append("")
        lines.append("Last reset: \(format(diagnostics.lastResetAt))")
        lines.append("Last error: \(diagnostics.lastError ?? "none")")
        return lines.joined(separator: "\n")
    }

    private func format(_ value: Int?) -> String {
        value.map(String.init) ?? "none"
    }

    private func format(_ value: Int64?) -> String {
        value.map(String.init) ?? "none"
    }

    private func format(_ value: Bool?) -> String {
        guard let value else {
            return "none"
        }
        return value ? "yes" : "no"
    }

    private func format(_ value: Double?) -> String {
        value.map { String($0) } ?? "none"
    }

    private func format(_ date: Date?) -> String {
        guard let date else {
            return "none"
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
