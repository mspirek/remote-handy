import ApplicationServices
import Foundation

enum AccessibilityPermission {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
