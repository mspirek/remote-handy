import AppKit
import CoreGraphics
import RemoteHandyCore

/// Prevents Handy's competing paste only while this helper owns a remote dictation.
/// Source PID matching excludes physical keys and this helper's System Events paste.
final class HandyPasteGuard {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var expiresAt = Date.distantPast
    private var handyPID: pid_t?
    private var targetPID: pid_t?
    private var policy = HandyPasteFilter()
    var suppressedPasteCount: Int { policy.suppressedPasteCount }
    private(set) var failed = false
    var suppressionComplete: Bool { policy.isComplete && !failed }

    func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let guardInstance = Unmanaged<HandyPasteGuard>.fromOpaque(context).takeUnretainedValue()
                return guardInstance.filter(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func begin(targetPID: pid_t) -> Bool {
        end()
        if tap == nil && !start() { return false }
        guard let tap, CGEvent.tapIsEnabled(tap: tap),
              let handy = NSRunningApplication.runningApplications(withBundleIdentifier: "com.pais.handy").first
        else { return false }
        expiresAt = Date().addingTimeInterval(180)
        handyPID = handy.processIdentifier
        self.targetPID = targetPID
        return true
    }

    func end() {
        handyPID = nil
        targetPID = nil
        policy = HandyPasteFilter()
        failed = false
    }

    func stop() {
        end()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func filter(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if handyPID != nil { failed = true }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if Date() > expiresAt { end() }
        let kind: PasteKeyEventKind
        switch type {
        case .keyDown: kind = .down
        case .keyUp: kind = .up
        case .flagsChanged: kind = .modifiers
        default: return Unmanaged.passUnretained(event)
        }
        if policy.shouldSuppress(
            kind: kind,
            key: event.getIntegerValueField(.keyboardEventKeycode),
            command: event.flags.contains(.maskCommand),
            sourcePID: event.getIntegerValueField(.eventSourceUnixProcessID),
            handyPID: handyPID.map(Int64.init),
            targetMatches: targetPID != nil && NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID
        ) { return nil }
        return Unmanaged.passUnretained(event)
    }
}
