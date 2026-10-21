import AppKit
import Foundation

enum SystemEventsAutomationError: Error, CustomStringConvertible {
    case appleScriptFailed(String)
    case automationNotAuthorized
    case keystrokesNotAllowed

    var description: String {
        switch self {
        case .appleScriptFailed(let detail):
            return "AppleScript failed: \(detail)"
        case .automationNotAuthorized:
            return "Remote Handy is not authorized to control System Events. Open System Settings > Privacy & Security > Automation and enable System Events under Remote Handy."
        case .keystrokesNotAllowed:
            let codeSigningStatus = CodeSigningDiagnostics.currentAppStatus()
            return "Remote Handy is not allowed to send keystrokes. \(codeSigningStatus.summary). Open Diagnostics or Check Input Permissions to confirm whether this install is signed with the stable local identity."
        }
    }
}

enum SystemEventsAutomation {
    static func checkPermission() throws {
        try run(
            """
            tell application "System Events"
                count processes
            end tell
            """
        )
    }

    static func sendKeyCode(_ keyCode: CGKeyCode) throws {
        try run(
            """
            tell application "System Events"
                key code \(keyCode)
            end tell
            """
        )
    }

    static func sendPaste() throws {
        try run(
            """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """
        )
    }

    static func sendKeyCodesThenPaste(_ keyCodes: [CGKeyCode], interKeyDelay: TimeInterval = 0.05) throws {
        var lines = [
            "tell application \"System Events\""
        ]

        for keyCode in keyCodes {
            lines.append("    key code \(keyCode)")
            lines.append("    delay \(interKeyDelay)")
        }

        lines.append("    keystroke \"v\" using command down")
        lines.append("end tell")
        try run(lines.joined(separator: "\n"))
    }

    private static func run(_ source: String) throws {
        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: "with timeout of 5 seconds\n" + source + "\nend timeout") else {
            throw SystemEventsAutomationError.appleScriptFailed("could not compile script")
        }

        appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int
            if errorNumber == -1743 {
                throw SystemEventsAutomationError.automationNotAuthorized
            }
            if errorNumber == 1002 {
                throw SystemEventsAutomationError.keystrokesNotAllowed
            }
            throw SystemEventsAutomationError.appleScriptFailed("\(errorInfo)")
        }
    }
}
