import AppKit
import Foundation
import RemoteHandyCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let windowWidth: CGFloat = 660
    private static let labelX: CGFloat = 8
    private static let labelWidth: CGFloat = 154
    private static let controlX: CGFloat = 178
    private static let rightMargin: CGFloat = 14

    var settings: AppSettings {
        didSet {
            loadSettingsIntoFields()
        }
    }

    private let onSave: (AppSettings) -> Void
    private let handyPostProcessButton = NSButton(checkboxWithTitle: "Handy: Option+Shift+Space", target: nil, action: nil)
    private let handyPathField = NSTextField()
    private let donorPathField = NSTextField()
    private let timeoutField = NSTextField()
    private let hotkeyMinimumHoldField = NSTextField()
    private let hiddenDonorButton = NSButton(checkboxWithTitle: "Hide donor window", target: nil, action: nil)
    private let automaticPasteButton = NSButton(checkboxWithTitle: "Auto paste", target: nil, action: nil)
    private let controlModifierButton = NSButton(checkboxWithTitle: "Ctrl", target: nil, action: nil)
    private let optionModifierButton = NSButton(checkboxWithTitle: "Opt", target: nil, action: nil)
    private let shiftModifierButton = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)
    private let commandModifierButton = NSButton(checkboxWithTitle: "Cmd", target: nil, action: nil)
    private let functionModifierButton = NSButton(checkboxWithTitle: "Fn", target: nil, action: nil)
    private let automaticTriggerButton = NSButton(
        checkboxWithTitle: "Enable Dictation shortcut trigger",
        target: nil,
        action: nil
    )

    init(
        settings: AppSettings,
        onSave: @escaping (AppSettings) -> Void
    ) {
        self.settings = settings
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Remote Handy Settings"
        window.center()

        super.init(window: window)
        buildContent()
        loadSettingsIntoFields()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildContent() {
        guard let window else {
            return
        }

        let contentView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: Self.windowWidth, height: 450))
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        handyPostProcessButton.frame = NSRect(x: Self.controlX, y: 450, width: 380, height: 26)
        contentView.addSubview(handyPostProcessButton)
        addLabel("Handy DB Path", y: 506, to: contentView)
        configurePathField(handyPathField, y: 500, in: contentView)


        addLabel("Donor App Path", y: 406, to: contentView)
        configurePathField(donorPathField, y: 400, in: contentView)

        addLabel("Timeout Seconds", y: 356, to: contentView)
        timeoutField.frame = NSRect(x: Self.controlX, y: 350, width: 90, height: 24)
        timeoutField.placeholderString = "20"
        contentView.addSubview(timeoutField)

        addLabel("Hide donor window", y: 314, to: contentView)
        configureCheckbox(hiddenDonorButton, label: "Hide donor window", y: 314, in: contentView)

        addLabel("Shortcut trigger", y: 278, to: contentView)
        configureCheckbox(automaticTriggerButton, label: "Shortcut trigger", y: 278, in: contentView)

        addLabel("Dictation Shortcut", y: 242, to: contentView)
        configureModifierButtons(y: 242, in: contentView)

        addLabel("Auto paste", y: 206, to: contentView)
        configureCheckbox(automaticPasteButton, label: "Auto paste", y: 206, in: contentView)



        addLabel("Min Hold Seconds", y: 98, to: contentView)
        hotkeyMinimumHoldField.frame = NSRect(x: Self.controlX, y: 92, width: 90, height: 24)
        hotkeyMinimumHoldField.placeholderString = "0.2"
        contentView.addSubview(hotkeyMinimumHoldField)

        let resetButton = NSButton(title: "Reset Defaults", target: self, action: #selector(resetDefaults))
        resetButton.frame = NSRect(x: 350, y: 18, width: 120, height: 32)
        contentView.addSubview(resetButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: 490, y: 18, width: 80, height: 32)
        contentView.addSubview(saveButton)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.frame = NSRect(x: 572, y: 18, width: 74, height: 32)
        contentView.addSubview(cancelButton)
    }

    private func addLabel(_ title: String, y: CGFloat, to contentView: NSView) {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: Self.labelX, y: y, width: Self.labelWidth, height: 20)
        label.alignment = .right
        contentView.addSubview(label)
    }

    private func configurePathField(_ field: NSTextField, y: CGFloat, in contentView: NSView) {
        field.frame = NSRect(
            x: Self.controlX,
            y: y,
            width: Self.windowWidth - Self.controlX - Self.rightMargin,
            height: 24
        )
        field.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(field)
    }

    private func configureCheckbox(_ button: NSButton, label: String, y: CGFloat, in contentView: NSView) {
        button.title = ""
        button.setAccessibilityLabel(label)
        button.frame = NSRect(x: Self.controlX, y: y, width: 24, height: 24)
        contentView.addSubview(button)
    }

    private func configureModifierButtons(y: CGFloat, in contentView: NSView) {
        let buttons = [
            controlModifierButton,
            optionModifierButton,
            shiftModifierButton,
            commandModifierButton,
            functionModifierButton
        ]
        let widths: [CGFloat] = [58, 52, 64, 60, 48]
        var x: CGFloat = Self.controlX
        for (button, width) in zip(buttons, widths) {
            button.frame = NSRect(x: x, y: y, width: width, height: 24)
            contentView.addSubview(button)
            x += width + 10
        }
    }

    private func loadSettingsIntoFields() {
        guard isWindowLoaded else {
            return
        }

        handyPostProcessButton.state = settings.handyPostProcessShortcutEnabled ? .on : .off
        handyPathField.stringValue = settings.handyDatabasePath
        donorPathField.stringValue = settings.donorAppPath
        timeoutField.stringValue = String(settings.waitTimeoutSeconds)
        hiddenDonorButton.state = settings.hiddenDonorEnabled ? .on : .off
        automaticTriggerButton.state = settings.automaticTriggerEnabled ? .on : .off
        automaticPasteButton.state = settings.automaticPasteEnabled ? .on : .off
        controlModifierButton.state = settings.hotkeyModifiers.contains(.control) ? .on : .off
        optionModifierButton.state = settings.hotkeyModifiers.contains(.option) ? .on : .off
        shiftModifierButton.state = settings.hotkeyModifiers.contains(.shift) ? .on : .off
        commandModifierButton.state = settings.hotkeyModifiers.contains(.command) ? .on : .off
        functionModifierButton.state = settings.hotkeyModifiers.contains(.function) ? .on : .off
        hotkeyMinimumHoldField.stringValue = String(settings.hotkeyMinimumHoldSeconds)
    }

    @objc private func resetDefaults() {
        settings = AppSettings()
        loadSettingsIntoFields()
    }

    @objc private func save() {
        var newSettings = settings
        newSettings.handyPostProcessShortcutEnabled = handyPostProcessButton.state == .on
        newSettings.handyDatabasePath = handyPathField.stringValue
        newSettings.donorAppPath = donorPathField.stringValue
        newSettings.waitTimeoutSeconds = Double(timeoutField.stringValue) ?? settings.waitTimeoutSeconds
        newSettings.hiddenDonorEnabled = hiddenDonorButton.state == .on
        newSettings.automaticTriggerEnabled = automaticTriggerButton.state == .on
        newSettings.hotkeyModifiers = selectedHotkeyModifiers()
        newSettings.automaticPasteEnabled = automaticPasteButton.state == .on
        let minimumHold = Double(hotkeyMinimumHoldField.stringValue) ?? settings.hotkeyMinimumHoldSeconds
        newSettings.hotkeyMinimumHoldSeconds = Swift.max(0, minimumHold)
        onSave(newSettings)
        close()
    }

    private func selectedHotkeyModifiers() -> [HotkeyModifier] {
        var modifiers: [HotkeyModifier] = []
        if controlModifierButton.state == .on {
            modifiers.append(.control)
        }
        if optionModifierButton.state == .on {
            modifiers.append(.option)
        }
        if shiftModifierButton.state == .on {
            modifiers.append(.shift)
        }
        if commandModifierButton.state == .on {
            modifiers.append(.command)
        }
        if functionModifierButton.state == .on {
            modifiers.append(.function)
        }
        return modifiers.isEmpty ? HotkeyModifier.defaultShortcut : modifiers
    }

    @objc private func cancel() {
        close()
    }
}
