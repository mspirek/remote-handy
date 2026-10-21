import Foundation
import ServiceManagement

@MainActor
enum StartupService {
    static let label = "com.remote-handy.agent"
    static var service: SMAppService { .agent(plistName: "\(label).plist") }
    static var summary: String {
        switch service.status {
        case .enabled: "Enabled: launch at login and recover after failure"
        case .requiresApproval: "Needs approval in System Settings > General > Login Items"
        case .notRegistered: "Disabled"
        case .notFound: "Service unavailable; reinstall the app"
        @unknown default: "Unknown service state"
        }
    }
    static func startManagedProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "gui/\(getuid())/\(label)"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "RemoteHandy.Startup", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Could not start the registered service; disable and enable startup again."])
        }
    }
    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
    static func enable() throws {
        if service.status == .enabled { try startManagedProcess() }
        else { try service.register() }
    }
    static func disable() async throws { try await service.unregister() }
    static func writeStatus(_ message: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RemoteHandy/startup-status.txt")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? message.write(to: url, atomically: true, encoding: .utf8)
    }
}
