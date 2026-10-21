import AppKit
import Foundation
import RemoteHandyCore

@MainActor
final class HotkeyTrigger {
    private let minimumHoldSeconds: TimeInterval
    private let requiredModifiers: [HotkeyModifier]
    private let keyCode: CGKeyCode?
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void
    private let onRejectedRelease: () -> Void
    private var hardwarePollTimer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isShortcutDown = false
    private var downAt: Date?

    init(
        minimumHoldSeconds: TimeInterval,
        requiredModifiers: [HotkeyModifier],
        keyCode: CGKeyCode? = nil,
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void,
        onRejectedRelease: @escaping () -> Void = {}
    ) {
        self.keyCode = keyCode
        self.minimumHoldSeconds = minimumHoldSeconds
        self.requiredModifiers = HotkeyModifier.ordered(requiredModifiers)
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onRejectedRelease = onRejectedRelease
    }

    func start() {
        stop()

        if requiredModifiers.contains(.function) || keyCode != nil {
            // Dictation apps consume Fn before it reaches the normal session event stream.
            // Hardware state remains visible; also check key 63 because arrow keys
            // can carry the secondary-Fn flag without the physical Fn key being held.
            hardwarePollTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let rawFlags = CGEventSource.flagsState(.hidSystemState).rawValue
                    let flags = NSEvent.ModifierFlags(rawValue: UInt(rawFlags))
                    let physicalFnDown = CGEventSource.keyState(.hidSystemState, key: self.keyCode ?? 63)
                    self.handleShortcutState(physicalFnDown && self.isRequiredShortcutDown(flags))
                }
            }
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        hardwarePollTimer?.invalidate()
        hardwarePollTimer = nil
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        isShortcutDown = false
        downAt = nil
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        handleShortcutState(isRequiredShortcutDown(flags))
    }

    private func handleShortcutState(_ shortcutDown: Bool) {
        if shortcutDown && !isShortcutDown {
            isShortcutDown = true
            downAt = Date()
            onKeyDown()
            return
        }

        if !shortcutDown && isShortcutDown {
            let heldSeconds = Date().timeIntervalSince(downAt ?? Date())
            isShortcutDown = false
            downAt = nil

            guard heldSeconds >= minimumHoldSeconds else {
                onRejectedRelease()
                return
            }

            onKeyUp()
        }
    }

    private func isRequiredShortcutDown(_ flags: NSEvent.ModifierFlags) -> Bool {
        let actual = Set(HotkeyModifier.allCases.filter { flags.contains($0.eventFlag) })
        let required = Set(requiredModifiers)
        return actual == required
    }
}

private extension HotkeyModifier {
    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .control:
            .control
        case .option:
            .option
        case .shift:
            .shift
        case .command:
            .command
        case .function:
            .function
        }
    }
}
