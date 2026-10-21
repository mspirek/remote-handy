import AppKit
import Foundation

struct DonorOptions {
    var textFile: String?
    var readyFile: String?
    var hiddenWindow = false
    var returnPID: pid_t?
}

struct ClipboardCopyResult {
    let clipboardLength: Int
    let clipboardMatches: Bool
}

@main
@MainActor
final class DonorApp: NSObject, NSApplicationDelegate {
    private let options: DonorOptions
    private var window: NSWindow?
    private var textView: NSTextView?

    override init() {
        self.options = Self.parseOptions(CommandLine.arguments.dropFirst())
        super.init()
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = DonorApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let text = loadText(), requestIsValid,
              options.returnPID == nil || NSWorkspace.shared.frontmostApplication?.processIdentifier == options.returnPID else {
            NSApp.terminate(nil)
            return
        }
        showWindow(text: text)
        let copyResult = copyText(text)
        handOffFocus()
        runLoopBriefly(seconds: 0.2)
        writeReadyFile(text: text, copyResult: copyResult)
        window?.orderOut(nil)
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private var requestIsValid: Bool {
        guard let path = options.textFile else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private var ownsFocus: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private func loadText() -> String? {
        guard let textFile = options.textFile,
              let text = try? String(contentsOfFile: textFile, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private func showWindow(text: String) {
        let contentRect = options.hiddenWindow
            ? NSRect(x: -10_000, y: -10_000, width: 32, height: 32)
            : NSRect(x: 0, y: 0, width: 620, height: 220)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: options.hiddenWindow ? [.borderless] : [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Remote Handy Copy Donor"

        if options.hiddenWindow {
            window.alphaValue = 0.01
            window.isOpaque = false
            window.ignoresMouseEvents = true
        } else {
            window.center()
        }

        let scrollViewFrame = options.hiddenWindow
            ? NSRect(x: 0, y: 0, width: 32, height: 32)
            : NSRect(x: 16, y: 48, width: 588, height: 156)
        let scrollView = NSScrollView(frame: scrollViewFrame)
        scrollView.hasVerticalScroller = true

        let textView = NSTextView(frame: scrollView.bounds)
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 18)
        scrollView.documentView = textView

        let label = NSTextField(labelWithString: "Copied for Remote Handy.")
        label.frame = NSRect(x: 16, y: 16, width: 588, height: 20)

        let contentView = NSView(frame: NSRect(origin: .zero, size: contentRect.size))
        contentView.addSubview(scrollView)
        if !options.hiddenWindow {
            contentView.addSubview(label)
        }
        window.contentView = contentView

        NSApplication.shared.activate(ignoringOtherApps: true)
        if options.hiddenWindow {
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
        }
        window.makeFirstResponder(textView)

        self.window = window
        self.textView = textView
        runLoopBriefly(seconds: 0.2)
    }

    private func copyText(_ text: String) -> ClipboardCopyResult {
        guard requestIsValid, ownsFocus, let textView else {
            return ClipboardCopyResult(clipboardLength: 0, clipboardMatches: false)
        }

        let pasteboard = NSPasteboard.general
        for _ in 0..<5 {
            guard requestIsValid, ownsFocus else { return ClipboardCopyResult(clipboardLength: 0, clipboardMatches: false) }
            textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
            runLoopBriefly(seconds: 0.1)
            guard requestIsValid, ownsFocus else { return ClipboardCopyResult(clipboardLength: 0, clipboardMatches: false) }
            textView.copy(nil)
            runLoopBriefly(seconds: 0.2)

            if let clipboard = pasteboard.string(forType: .string),
               clipboard == text {
                return ClipboardCopyResult(clipboardLength: clipboard.count, clipboardMatches: true)
            }

            guard requestIsValid, ownsFocus else { return ClipboardCopyResult(clipboardLength: 0, clipboardMatches: false) }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            runLoopBriefly(seconds: 0.2)

            if let clipboard = pasteboard.string(forType: .string),
               clipboard == text {
                return ClipboardCopyResult(clipboardLength: clipboard.count, clipboardMatches: true)
            }
        }

        let clipboard = pasteboard.string(forType: .string) ?? ""
        return ClipboardCopyResult(clipboardLength: clipboard.count, clipboardMatches: clipboard == text)
    }

    private func writeReadyFile(text: String, copyResult: ClipboardCopyResult) {
        guard let readyFile = options.readyFile else {
            return
        }

        let body = """
        ready
        expectedLength=\(text.count)
        clipboardLength=\(copyResult.clipboardLength)
        clipboardMatches=\(copyResult.clipboardMatches ? "yes" : "no")
        """

        try? body.write(toFile: readyFile, atomically: true, encoding: .utf8)
    }

    private func handOffFocus() {
        guard requestIsValid, ownsFocus, let returnPID = options.returnPID,
              let returnApplication = NSRunningApplication(processIdentifier: returnPID) else {
            return
        }

        _ = returnApplication.activate(options: [.activateIgnoringOtherApps])
    }

    private func runLoopBriefly(seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.current.run(mode: .default, before: end)
        }
    }

    private static func parseOptions(_ args: ArraySlice<String>) -> DonorOptions {
        var options = DonorOptions()
        var iterator = args.makeIterator()

        while let arg = iterator.next() {
            switch arg {
            case "--text-file":
                options.textFile = iterator.next()
            case "--ready-file":
                options.readyFile = iterator.next()
            case "--hidden-window":
                options.hiddenWindow = true
            case "--return-pid":
                if let value = iterator.next(), let pid = Int32(value) {
                    options.returnPID = pid
                }
            default:
                continue
            }
        }

        return options
    }
}
