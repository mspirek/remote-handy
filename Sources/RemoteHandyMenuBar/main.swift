import AppKit
import Foundation
import RemoteHandyCore

@MainActor
final class RemoteHandyMenuBarApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let instanceLock = SingleInstanceLock()
    private var sessionActive = true
    private var startupAttempts = 0
    private var startupMonitor: Timer?
    private let startupMenuItem = NSMenuItem(title: "Launch at Login & Recover After Failure", action: #selector(toggleStartup), keyEquivalent: "")
    private var wakeObservers: [NSObjectProtocol] = []
    private let statusMenuItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
    private let copyMenuItem = NSMenuItem(title: "Copy Next Transcript", action: #selector(copyNextTranscript), keyEquivalent: "")
    private let checkMenuItem = NSMenuItem(title: "Check Transcript DB", action: #selector(checkTranscriptDatabase), keyEquivalent: "")
    private let baselineHealthMenuItem = NSMenuItem(title: "Run Baseline Health Check", action: #selector(runBaselineHealthCheck), keyEquivalent: "")
    private let inputPermissionMenuItem = NSMenuItem(title: "Check Input Permissions", action: #selector(checkInputPermissions), keyEquivalent: "")
    private let diagnosticsMenuItem = NSMenuItem(title: "Diagnostics...", action: #selector(openDiagnostics), keyEquivalent: "")
    private let settingsMenuItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
    private let manualDisableMenuItem = NSMenuItem(title: "Disable Remote Handy", action: #selector(toggleManualDisable), keyEquivalent: "")
    private let resetMenuItem = NSMenuItem(title: "Reset Running State", action: #selector(resetRunningState), keyEquivalent: "")
    private let openLogMenuItem = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
    private let logURL = RemoteHandyMenuBarApp.defaultLogURL()
    private let settingsStore = SettingsStore(fileURL: RemoteHandyMenuBarApp.defaultSettingsURL())
    private let baselineHealthChecker = BaselineHealthChecker()
    private let handyPasteGuard = HandyPasteGuard()
    private let remoteInputAutomationController = RemoteInputAutomationController()
    private var settings = AppSettings()
    private var runningTask: Task<Void, Never>?
    private var lastStatus = "Idle"
    private var settingsWindowController: SettingsWindowController?
    private var diagnosticsWindowController: DiagnosticsWindowController?
    private var hotkeyTrigger: HotkeyTrigger?
    private var handyPostProcessTrigger: HotkeyTrigger?
    private var isManuallyDisabled = false
    private var hotkeyMarkerRowID: Int64?
    private var hotkeyTargetApplication: NSRunningApplication?
    private var readyTitleClearTimer: Timer?
    private var diagnostics = AppDiagnostics()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.contains("--check-permissions") {
            checkInputPermissions()
            NSApp.terminate(nil)
            return
        }
        if args.contains("--startup-enable") || args.contains("--startup-disable") || args.contains("--startup-status") {
            Task { @MainActor in
                do {
                    if args.contains("--startup-enable") { try StartupService.enable() }
                    if args.contains("--startup-disable") { try await StartupService.disable() }
                    StartupService.writeStatus(StartupService.summary)
                    if args.contains("--startup-enable") && StartupService.service.status != .enabled {
                        startNormalSession()
                        setStatus(StartupService.summary)
                        openSettings()
                        if StartupService.service.status == .requiresApproval { StartupService.openSettings() }
                        return
                    }
                } catch {
                    StartupService.writeStatus("Error: \(error)")
                    startNormalSession()
                    setStatus("Startup error: \(error)")
                    openSettings()
                    return
                }
                NSApp.terminate(nil)
            }
            return
        }
        startNormalSession()
    }

    private func startNormalSession() {
        if !CommandLine.arguments.contains("--managed"), StartupService.service.status == .enabled {
            do {
                try StartupService.startManagedProcess()
                NSApp.terminate(nil)
                return
            } catch { appendLog("startup ownership error: \(error)") }
        }
        do {
            let acquired = try instanceLock.acquire(at: Self.defaultSettingsURL().deletingLastPathComponent().appendingPathComponent("instance.lock"))
            guard acquired else {
                // A newly registered managed process may overlap the quitting manual app.
                if CommandLine.arguments.contains("--managed") && startupAttempts < 40 {
                    startupAttempts += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.startNormalSession() }
                } else { NSApp.terminate(nil) }
                return
            }
        } catch {
            appendLog("instance lock failed: \(error)")
            NSApp.terminate(nil)
            return
        }
        loadSettings()
        configureMenu()
        configureHotkeyTrigger()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            wakeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspendForSessionChange() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            wakeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sessionActive = true
                    self?.configureHotkeyTrigger()
                    self?.appendLog("session resumed; hotkeys rearmed")
                }
            })
        }
        if !CommandLine.arguments.contains("--managed") {
            startupMonitor = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.runningTask == nil, self.hotkeyMarkerRowID == nil,
                          StartupService.service.status == .enabled else { return }
                    do {
                        try StartupService.startManagedProcess()
                        NSApp.terminate(nil)
                    } catch { self.setStatus("Startup error: \(error)") }
                }
            }
        }
        setStatus(isManuallyDisabled ? "Disabled" : "Idle")
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }

    private func suspendForSessionChange() {
        sessionActive = false
        runningTask?.cancel()
        hotkeyMarkerRowID = nil
        hotkeyTargetApplication = nil
        handyPasteGuard.stop()
        hotkeyTrigger?.stop()
        handyPostProcessTrigger?.stop()
        appendLog("session suspended; pending operation cancelled")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    @objc private func toggleStartup() {
        Task { @MainActor in
            do {
                if StartupService.service.status == .enabled || StartupService.service.status == .requiresApproval {
                    try await StartupService.disable()
                } else {
                    try StartupService.enable()
                    // Transfer process ownership to launchd; the managed process waits for our lock.
                    if StartupService.service.status == .enabled {
                        try StartupService.startManagedProcess()
                        NSApp.terminate(nil)
                    } else if StartupService.service.status == .requiresApproval { StartupService.openSettings() }
                }
                startupMenuItem.state = StartupService.service.status == .enabled ? .on : .off
                setStatus(StartupService.summary)
            } catch { setStatus("Startup error: \(error)") }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupMonitor?.invalidate()
        for observer in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        runningTask?.cancel()
        handyPasteGuard.stop()
        handyPostProcessTrigger?.stop()
        handyPostProcessTrigger = nil
        hotkeyTrigger?.stop()
        readyTitleClearTimer?.invalidate()
    }

    private func configureMenu() {
        if let button = statusItem.button {
            button.title = "RH"
            button.toolTip = "Remote Handy"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())

        copyMenuItem.target = self
        menu.addItem(copyMenuItem)

        checkMenuItem.target = self
        menu.addItem(checkMenuItem)

        baselineHealthMenuItem.target = self
        menu.addItem(baselineHealthMenuItem)

        inputPermissionMenuItem.target = self
        menu.addItem(inputPermissionMenuItem)

        diagnosticsMenuItem.target = self
        menu.addItem(diagnosticsMenuItem)

        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)
        startupMenuItem.target = self
        startupMenuItem.state = StartupService.service.status == .enabled ? .on : .off
        menu.addItem(startupMenuItem)

        manualDisableMenuItem.target = self
        menu.addItem(manualDisableMenuItem)

        resetMenuItem.target = self
        menu.addItem(resetMenuItem)

        openLogMenuItem.target = self
        menu.addItem(openLogMenuItem)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        appendLog("app launched")
    }

    @objc private func statusItemClicked() {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if flags.contains(.option) {
            toggleManualDisable()
            appendLog("manual disable toggled by option-click")
            return
        }

        if let button = statusItem.button {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: button.bounds.height),
                in: button
            )
        }
    }

    @objc private func copyNextTranscript() {
        guard runningTask == nil else {
            setStatus("Already running")
            return
        }

        copyMenuItem.isEnabled = false
        runningTask = Task { [weak self] in
            await self?.runCopyNextTranscript()
        }
    }

    @objc private func checkTranscriptDatabase() {
        guard runningTask == nil else {
            setStatus("Already running")
            return
        }

        runningTask = Task { [weak self] in
            await self?.runDatabaseCheck()
        }
    }

    @objc private func runBaselineHealthCheck() {
        guard runningTask == nil else {
            setStatus("Already running")
            return
        }

        let report = baselineHealthChecker.run(
            settings: settings,
            resolvedDonorAppPath: resolvedDonorAppPath(settings),
            settingsPath: Self.defaultSettingsURL().path,
            appVersion: Self.bundleValue("CFBundleShortVersionString", defaultValue: "development"),
            appBuild: Self.bundleValue("CFBundleVersion", defaultValue: "development")
        )

        diagnostics.lastBaselineHealthReport = report
        diagnostics.lastError = report.passed ? nil : "Baseline health needs attention"
        setStatus(report.statusText == "ok with notes" ? "Health OK with notes" : report.passed ? "Health OK" : "Health needs attention")
        appendLog("baseline health \(report.statusText)")
        for item in report.items {
            appendLog("baseline health item name=\"\(item.name)\" status=\(item.statusText) detail=\"\(item.detail)\"")
        }
    }

    @objc private func checkInputPermissions() {
        diagnostics.lastInputPermissionCheckAt = Date()
        let codeSigningStatus = CodeSigningDiagnostics.currentAppStatus()
        diagnostics.lastCodeSigningStatus = codeSigningStatus
        appendLog("input permission code signing \(codeSigningStatus.summary)")
        let accessibilityTrusted = AccessibilityPermission.isTrusted(prompt: true)
        guard accessibilityTrusted else {
            let installPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Remote Handy.app")
                .path
            let message = "Accessibility is not enabled for this signed Remote Handy app. \(codeSigningStatus.summary). Open System Settings > Privacy & Security > Accessibility, remove stale Remote Handy entries, then add \(installPath)."
            diagnostics.lastInputPermissionResult = message
            diagnostics.lastError = message
            setStatus("Input permission needed")
            appendLog("input permission accessibility error=\(message)")
            diagnosticsWindowController?.refresh()
            return
        }

        do {
            try SystemEventsAutomation.checkPermission()
            diagnostics.lastInputPermissionResult = "ok - Accessibility enabled and Remote Handy can control System Events"
            diagnostics.lastError = nil
            setStatus("Input permissions OK")
            appendLog("input permissions ok")
        } catch {
            let message = String(describing: error)
            diagnostics.lastInputPermissionResult = message
            diagnostics.lastError = message
            setStatus("Input permission needed")
            appendLog("input permission automation error=\(message)")
        }
        diagnosticsWindowController?.refresh()
    }

    @objc private func quit() {
        appendLog("quit")
        NSApplication.shared.terminate(nil)
    }

    @objc private func openLog() {
        ensureLogDirectory()
        if !FileManager.default.fileExists(atPath: logURL.path) {
            appendLog("log created")
        }
        NSWorkspace.shared.open(logURL)
    }

    @objc private func openDiagnostics() {
        if diagnosticsWindowController == nil {
            diagnosticsWindowController = DiagnosticsWindowController(
                snapshotProvider: { [weak self] in
                    self?.makeDiagnosticsSnapshot() ?? Self.emptyDiagnosticsSnapshot()
                },
                onOpenLog: { [weak self] in
                    self?.openLog()
                }
            )
        }

        diagnosticsWindowController?.refresh()
        diagnosticsWindowController?.showWindow(nil)
        diagnosticsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings
            ) { [weak self] newSettings in
                self?.saveSettings(newSettings)
            }
        }

        settingsWindowController?.settings = settings
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func toggleManualDisable() {
        handyPasteGuard.stop()
        isManuallyDisabled.toggle()
        if isManuallyDisabled { runningTask?.cancel() }
        diagnostics.isManuallyDisabled = isManuallyDisabled
        updateManualDisableMenuItem()
        hotkeyMarkerRowID = nil
        hotkeyTargetApplication = nil
        diagnostics.hotkeyMarkerRowID = nil
        let message = isManuallyDisabled ? "Disabled" : "Enabled"
        setStatus(message)
        appendLog("manual disable toggled disabled=\(isManuallyDisabled)")
    }

    @objc private func resetRunningState() {
        handyPasteGuard.stop()
        runningTask?.cancel()
        // Keep the task reserved until its cancellation defer completes.
        hotkeyMarkerRowID = nil
        hotkeyTargetApplication = nil
        diagnostics.lastSkippedReason = nil
        diagnostics.isRunning = false
        diagnostics.hotkeyMarkerRowID = nil
        diagnostics.lastError = nil
        diagnostics.lastResetAt = Date()
        copyMenuItem.isEnabled = true
        setStatus("Reset")
        appendLog("running state reset")
    }

    private func runCopyNextTranscript() async {
        do {
            let store = settings.makeTranscriptStore()
            let afterRowID = try store.maxRowID()
            let target = NSWorkspace.shared.frontmostApplication
            do {
                guard let target,
                      target.bundleIdentifier == "com.apple.ScreenSharing",
                      handyPasteGuard.begin(targetPID: target.processIdentifier) else {
                    throw NSError(domain: "RemoteHandy", code: 3, userInfo: [NSLocalizedDescriptionKey: "Handy copy-next requires Screen Sharing frontmost and a working paste guard."])
                }
            }
            diagnostics.lastMarkerRowID = afterRowID
            await runCopyNextTranscript(afterRowID: afterRowID, source: "menu", cleanupTargetApplication: target)
        } catch {
            if Task.isCancelled {
                appendLog("copy next marker cancelled")
                return
            }
            runningTask = nil
            copyMenuItem.isEnabled = true
            diagnostics.isRunning = false
            diagnostics.lastError = String(describing: error)
            setStatus("Error: \(error)")
            appendLog("copy next marker error=\(error)")
        }
    }

    private func runCopyNextTranscript(
        afterRowID: Int64,
        source: String,
        cleanupTargetApplication: NSRunningApplication?
    ) async {
        defer {
            handyPasteGuard.stop()
            runningTask = nil
            copyMenuItem.isEnabled = true
            diagnostics.isRunning = false
            diagnosticsWindowController?.refresh()
        }

        do {
            let currentSettings = settings
            let store = currentSettings.makeTranscriptStore()
            diagnostics.isRunning = true
            diagnostics.lastTriggerSource = source
            diagnostics.lastOperationStartedAt = Date()
            diagnostics.lastMarkerRowID = afterRowID
            diagnostics.lastError = nil
            diagnostics.lastDonorClipboardMatches = nil
            diagnostics.lastAutoPasteEnabled = nil
            diagnostics.lastAutoPasteResult = nil
            setStatus("Waiting after row \(afterRowID)")
            appendLog("copy next started source=\(source) afterRowID=\(afterRowID)")

            let watcher = TranscriptWatcher(store: store, pollIntervalSeconds: currentSettings.pollIntervalSeconds)
            let row = try await watcher.waitForNext(after: afterRowID, timeoutSeconds: currentSettings.waitTimeoutSeconds)
            do {
                let suppressed = handyPasteGuard.suppressedPasteCount
                appendLog("Handy native paste suppressed=\(suppressed) guardFailed=\(handyPasteGuard.failed)")
                guard handyPasteGuard.suppressionComplete else {
                    throw NSError(domain: "RemoteHandy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Handy paste prevention was not verified; no helper clipboard change or paste sent."])
                }
                // Native key pair is complete. Remove the tap before synchronous donor/AppleScript work.
                handyPasteGuard.stop()
            }
            diagnostics.lastRowSeen = row
            setStatus("Copying row \(row.rowID)")
            appendLog("row found rowID=\(row.rowID) length=\(row.text.count)")
            if  NSWorkspace.shared.frontmostApplication?.processIdentifier != cleanupTargetApplication?.processIdentifier {
                setStatus("Skipped: focus changed")
                appendLog("copy skipped before donor: focus changed")
                return
            }
            let cleanupTargetApplication = cleanupTargetApplication ?? NSWorkspace.shared.frontmostApplication

            let donor = PersistentDonorApp(
                appPath: resolvedDonorAppPath(currentSettings),
                hiddenWindow: currentSettings.hiddenDonorEnabled
            )
            let clipboardText = ClipboardTextFormatter.appendTrailingSpace(row.text)
            try Task.checkCancellation()
            guard sessionActive else { throw CancellationError() }
            let result = try await donor.copyText(
                clipboardText,
                returnProcessIdentifier: cleanupTargetApplication?.processIdentifier
            )
            await Task.yield()
            try Task.checkCancellation()
            guard sessionActive else { throw CancellationError() }
            let clipboardMatches = result.readyContents.contains("clipboardMatches=yes") && NSPasteboard.general.string(forType: .string) == clipboardText
            diagnostics.lastCopiedRowID = row.rowID
            diagnostics.lastCopiedLength = clipboardText.count
            diagnostics.lastDonorClipboardMatches = clipboardMatches
            diagnostics.lastDonorReadyAt = Date()
            diagnostics.lastDonorHandoffWaitSeconds = result.handoffWaitSeconds
            diagnostics.lastDonorStillFrontmost = result.donorStillFrontmost
            var autoPasteResult: RemoteInputAutomationResult?
            if clipboardMatches {
                autoPasteResult = try await runAutoPasteIfEnabled(settings: currentSettings, targetApplication: cleanupTargetApplication)
            }
            if clipboardMatches, currentSettings.automaticPasteEnabled, autoPasteResult?.didRun == true {
                setStatus("Paste sent row \(row.rowID)")
            } else {
                setStatus(clipboardMatches ? "Ready row \(row.rowID)" : "Copy verify failed")
            }
            appendLog("donor ready rowID=\(row.rowID) clipboardMatches=\(clipboardMatches) handoffWait=\(result.handoffWaitSeconds) donorStillFrontmost=\(result.donorStillFrontmost)")
        } catch {
            if Task.isCancelled {
                appendLog("copy next cancelled")
                return
            }
            let message = userFacingCopyError(error)
            diagnostics.lastError = message
            setStatus("Error: \(message)")
            appendLog("copy next error=\(message)")
        }
    }

    private func userFacingCopyError(_ error: Error) -> String {
        if case TranscriptWatcherError.timeout(let afterRowID) = error {
            return "Timed out waiting after row \(afterRowID). Confirm Handy history is enabled and contains a new dictation."
        }

        return String(describing: error)
    }

    private func runAutoPasteIfEnabled(settings: AppSettings, targetApplication: NSRunningApplication?) async throws -> RemoteInputAutomationResult {
        let enabled = settings.automaticPasteEnabled
        diagnostics.lastAutoPasteEnabled = enabled
        diagnostics.lastAutoPasteAt = Date()

        guard enabled else {
            diagnostics.lastAutoPasteResult = "disabled"
            appendLog("auto paste disabled")
            return RemoteInputAutomationResult(didRun: false, detail: "disabled")
        }

        try Task.checkCancellation()
        guard sessionActive else { throw CancellationError() }
        let result = try await remoteInputAutomationController.pasteIntoScreenSharing(
            targetApplication: targetApplication
        )
        diagnostics.lastAutoPasteResult = result.detail
        appendLog("auto paste ran=\(result.didRun) detail=\"\(result.detail)\"")
        return result
    }

    private func runDatabaseCheck() async {
        defer {
            runningTask = nil
            diagnostics.isRunning = false
            diagnosticsWindowController?.refresh()
        }

        do {
            diagnostics.isRunning = true
            diagnostics.lastError = nil
            let store = settings.makeTranscriptStore()
            let maxRowID = try store.maxRowID()
            diagnostics.lastDatabaseCheckAt = Date()
            diagnostics.lastDatabaseMaxRowID = maxRowID
            if maxRowID > 0 {
                setStatus("DB OK, max row \(maxRowID)")
                appendLog("db check ok maxRowID=\(maxRowID)")
            } else {
                setStatus("DB warning, max row 0")
                appendLog("db check warning maxRowID=0 reason=handy-history-may-be-disabled")
            }
        } catch {
            if Task.isCancelled {
                appendLog("db check cancelled")
                return
            }
            diagnostics.lastError = String(describing: error)
            setStatus("DB error: \(error)")
            appendLog("db check error=\(error)")
        }
    }

    private func setStatus(_ message: String) {
        readyTitleClearTimer?.invalidate()
        readyTitleClearTimer = nil
        lastStatus = message
        diagnostics.status = message
        let display = message.count > 64 ? String(message.prefix(61)) + "..." : message
        statusMenuItem.title = display
        statusItem.button?.title = statusTitle(for: message)
        scheduleReadyTitleClearIfNeeded(for: message)
        diagnosticsWindowController?.refresh()
    }

    private func scheduleReadyTitleClearIfNeeded(for message: String) {
        guard message.hasPrefix("Ready") || message.hasPrefix("Paste sent") else {
            return
        }

        readyTitleClearTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.lastStatus == message else {
                    return
                }
                self.statusItem.button?.title = "RH"
                self.readyTitleClearTimer = nil
            }
        }
    }

    private func loadSettings() {
        do {
            settings = try settingsStore.loadOrCreate(defaultSettings: Self.defaultAppSettings())
            appendLog("settings loaded or created schemaVersion=\(settings.settingsSchemaVersion)")
        } catch {
            settings = AppSettings()
            isManuallyDisabled = true
            appendLog("settings load failed error=\(error)")
        }
    }

    private func saveSettings(_ newSettings: AppSettings) {
        do {
            guard runningTask == nil else {
                setStatus("Wait for the current transcript before changing settings")
                return
            }
            hotkeyMarkerRowID = nil
            hotkeyTargetApplication = nil
            diagnostics = AppDiagnostics()
            try settingsStore.save(newSettings)
            settings = newSettings
            configureHotkeyTrigger()
            appendLog("settings saved")
            setStatus("Settings saved")
        } catch {
            appendLog("settings save error=\(error)")
            setStatus("Settings error: \(error)")
        }
    }

    private func resolvedDonorAppPath(_ settings: AppSettings) -> String {
        settings.donorAppPath.isEmpty ? Self.defaultDonorAppPath() : settings.donorAppPath
    }

    private static func defaultAppSettings() -> AppSettings {
        AppSettings(donorAppPath: defaultDonorAppPath())
    }

    private func configureHotkeyTrigger() {
        handyPasteGuard.stop()
        do {
            appendLog("Handy paste guard configured; armed only during remote dictation")
        }
        handyPostProcessTrigger?.stop()
        handyPostProcessTrigger = nil
        hotkeyTrigger?.stop()
        hotkeyTrigger = nil

        guard settings.automaticTriggerEnabled else {
            diagnostics.hotkeyEnabled = false
            appendLog("hotkey trigger disabled")
            return
        }

        diagnostics.hotkeyEnabled = true
        let trigger = HotkeyTrigger(
            minimumHoldSeconds: settings.hotkeyMinimumHoldSeconds,
            requiredModifiers: settings.hotkeyModifiers,
            onKeyDown: { [weak self] in
                self?.handleHotkeyDown()
            },
            onKeyUp: { [weak self] in
                self?.handleHotkeyUp()
            },
            onRejectedRelease: { [weak self] in self?.cancelHotkeyMarker() }
        )
        trigger.start()
        hotkeyTrigger = trigger
        if settings.handyPostProcessShortcutEnabled {
            let postProcessTrigger = HotkeyTrigger(
                minimumHoldSeconds: settings.hotkeyMinimumHoldSeconds,
                requiredModifiers: [.option, .shift],
                keyCode: 49,
                onKeyDown: { [weak self] in self?.handleHotkeyDown() },
                onKeyUp: { [weak self] in self?.handleHotkeyUp() },
                onRejectedRelease: { [weak self] in self?.cancelHotkeyMarker() }
            )
            postProcessTrigger.start()
            handyPostProcessTrigger = postProcessTrigger
            appendLog("Handy post-process trigger enabled shortcut=Option+Shift+Space")
        }
        appendLog("hotkey trigger enabled shortcut=\(HotkeyModifier.displayName(for: settings.hotkeyModifiers)) minimumHoldSeconds=\(settings.hotkeyMinimumHoldSeconds)")
    }

    private func cancelHotkeyMarker() {
        guard runningTask == nil else { return }
        handyPasteGuard.stop()
        hotkeyMarkerRowID = nil
        hotkeyTargetApplication = nil
        diagnostics.hotkeyMarkerRowID = nil
    }

    private func handleHotkeyDown() {
        guard sessionActive else { return }
        guard runningTask == nil else {
            setStatus("Busy: wait for the current paste")
            appendLog("hotkey down ignored already running")
            return
        }

        guard !isManuallyDisabled else {
            hotkeyMarkerRowID = nil
            hotkeyTargetApplication = nil
            diagnostics.hotkeyMarkerRowID = nil
            diagnostics.lastSkippedReason = "manual disable is on"
            appendLog("hotkey down skipped reason=manual-disabled")
            return
        }

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        guard frontmostApplication?.bundleIdentifier == Self.screenSharingBundleIdentifier else {
            let description = Self.describeApplication(frontmostApplication)
            hotkeyMarkerRowID = nil
            hotkeyTargetApplication = nil
            diagnostics.hotkeyMarkerRowID = nil
            diagnostics.lastSkippedReason = "frontmost app is not Screen Sharing: \(description)"
            appendLog("hotkey down skipped reason=not-screen-sharing frontmost=\"\(description)\"")
            return
        }

        do {
            let store = settings.makeTranscriptStore()
            let marker = try store.maxRowID()
            if
               !handyPasteGuard.begin(targetPID: frontmostApplication!.processIdentifier) {
                throw NSError(domain: "RemoteHandy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot guard Handy paste. Check existing Accessibility permission and that Handy is running."])
            }
            hotkeyMarkerRowID = marker
            hotkeyTargetApplication = frontmostApplication
            diagnostics.hotkeyMarkerRowID = marker
            diagnostics.lastMarkerRowID = marker
            diagnostics.lastSkippedReason = nil
            appendLog("hotkey down markerRowID=\(marker)")
        } catch {
            hotkeyMarkerRowID = nil
            hotkeyTargetApplication = nil
            diagnostics.hotkeyMarkerRowID = nil
            diagnostics.lastError = String(describing: error)
            appendLog("hotkey down error=\(error)")
            setStatus("Hotkey error: \(error)")
        }
    }

    private func handleHotkeyUp() {
        guard runningTask == nil else {
            appendLog("hotkey up ignored already running")
            return
        }

        guard !isManuallyDisabled else {
            hotkeyMarkerRowID = nil
            hotkeyTargetApplication = nil
            diagnostics.hotkeyMarkerRowID = nil
            diagnostics.lastSkippedReason = "manual disable is on"
            appendLog("hotkey up skipped reason=manual-disabled")
            return
        }

        guard let marker = hotkeyMarkerRowID else {
            appendLog("hotkey up ignored no marker")
            return
        }

        hotkeyMarkerRowID = nil
        let cleanupTargetApplication = hotkeyTargetApplication
        hotkeyTargetApplication = nil
        diagnostics.hotkeyMarkerRowID = nil
        copyMenuItem.isEnabled = false
        runningTask = Task { [weak self] in
            await self?.runCopyNextTranscript(
                afterRowID: marker,
                source: "hotkey",
                cleanupTargetApplication: cleanupTargetApplication
            )
        }
    }

    private func makeDiagnosticsSnapshot() -> DiagnosticsSnapshot {
        var currentMaxRowID: Int64?
        var currentMaxRowError: String?

        do {
            let store = settings.makeTranscriptStore()
            currentMaxRowID = try store.maxRowID()
        } catch {
            currentMaxRowError = String(describing: error)
        }

        var currentDiagnostics = diagnostics
        currentDiagnostics.isRunning = runningTask != nil
        currentDiagnostics.isManuallyDisabled = isManuallyDisabled
        currentDiagnostics.hotkeyEnabled = settings.automaticTriggerEnabled
        currentDiagnostics.hotkeyMarkerRowID = hotkeyMarkerRowID

        return DiagnosticsSnapshot(
            settings: settings,
            diagnostics: currentDiagnostics,
            currentMaxRowID: currentMaxRowID,
            currentMaxRowError: currentMaxRowError,
            donorAppPath: resolvedDonorAppPath(settings),
            logPath: logURL.path,
            appVersion: Self.bundleValue("CFBundleShortVersionString", defaultValue: "development"),
            appBuild: Self.bundleValue("CFBundleVersion", defaultValue: "development")
        )
    }

    private static func emptyDiagnosticsSnapshot() -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            settings: AppSettings(),
            diagnostics: AppDiagnostics(status: "Diagnostics unavailable"),
            currentMaxRowID: nil,
            currentMaxRowError: "app delegate unavailable",
            donorAppPath: defaultDonorAppPath(),
            logPath: defaultLogURL().path,
            appVersion: bundleValue("CFBundleShortVersionString", defaultValue: "development"),
            appBuild: bundleValue("CFBundleVersion", defaultValue: "development")
        )
    }

    private func appendLog(_ message: String) {
        ensureLogDirectory()
        let fileManager = FileManager.default
        if let attrs = try? fileManager.attributesOfItem(atPath: logURL.path),
           let size = attrs[.size] as? NSNumber, size.intValue > 1_048_576 {
            let previous = logURL.appendingPathExtension("previous")
            try? fileManager.removeItem(at: previous)
            try? fileManager.moveItem(at: logURL, to: previous)
        }
        let line = "\(Self.timestamp()) \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer {
                try? handle.close()
            }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    private func ensureLogDirectory() {
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func statusTitle(for message: String) -> String {
        if isManuallyDisabled || message == "Disabled" {
            return "RH Off"
        }
        if message.hasPrefix("Ready") {
            return "RH Ready"
        }
        if message.hasPrefix("Error")
            || message.localizedCaseInsensitiveContains("error")
            || message.localizedCaseInsensitiveContains("needs attention")
            || message.localizedCaseInsensitiveContains("failed") {
            return "RH Error"
        }
        if message == "Idle" || message == "Enabled" {
            return "RH"
        }
        if message.hasPrefix("DB OK")
            || message == "Settings saved"
            || message == "Reset"
            || message == "Health OK"
            || message == "Health OK with notes" {
            return "RH"
        }
        return "RH..."
    }

    private static var screenSharingBundleIdentifier: String {
        "com.apple.ScreenSharing"
    }

    private func updateManualDisableMenuItem() {
        manualDisableMenuItem.title = isManuallyDisabled ? "Enable Remote Handy" : "Disable Remote Handy"
    }

    private static func defaultDonorAppPath() -> String {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("Remote Handy Copy Donor.app")
                .path
        }

        return FileManager.default.currentDirectoryPath + "/.build/apps/Remote Handy Copy Donor.app"
    }

    private static func describeApplication(_ application: NSRunningApplication?) -> String {
        guard let application else {
            return "none"
        }
        let name = application.localizedName ?? "unknown"
        let bundleIdentifier = application.bundleIdentifier ?? "unknown"
        return "\(name)[\(bundleIdentifier)]"
    }

    private static func defaultLogURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/RemoteHandy/menu-bar.log")
    }

    private static func defaultSettingsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RemoteHandy/settings.json")
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func bundleValue(_ key: String, defaultValue: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? defaultValue
    }
}

let app = NSApplication.shared
let delegate = RemoteHandyMenuBarApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
