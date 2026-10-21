import AppKit
import Foundation

struct RemoteInputAutomationResult {
    let didRun: Bool
    let detail: String
}

@MainActor
final class RemoteInputAutomationController {
    func pasteIntoScreenSharing(
        targetApplication: NSRunningApplication?
    ) async throws -> RemoteInputAutomationResult {
        // Allow queued sleep/session/cancellation notifications to run before keys.
        await Task.yield()
        try Task.checkCancellation()
        guard targetApplication?.bundleIdentifier == "com.apple.ScreenSharing",
              NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApplication?.processIdentifier else {
            return RemoteInputAutomationResult(didRun: false, detail: "skipped: Screen Sharing is no longer frontmost; no keys sent")
        }
        // Donor already returned focus. Do not steal it back from a user-selected app.
        do {
            try SystemEventsAutomation.sendPaste()
            return RemoteInputAutomationResult(didRun: true, detail: "focusReady=true; sent command-v to Screen Sharing pid=\(targetApplication?.processIdentifier ?? -1)")
        } catch {
            return RemoteInputAutomationResult(didRun: false, detail: String(describing: error))
        }
    }
}
