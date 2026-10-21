import AppKit
import Foundation

@MainActor
final class DiagnosticsWindowController: NSWindowController {
    private let snapshotProvider: () -> DiagnosticsSnapshot
    private let onOpenLog: () -> Void
    private let textView = NSTextView()

    init(snapshotProvider: @escaping () -> DiagnosticsSnapshot, onOpenLog: @escaping () -> Void) {
        self.snapshotProvider = snapshotProvider
        self.onOpenLog = onOpenLog

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Remote Handy Diagnostics"
        window.center()

        super.init(window: window)
        buildContent()
        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func refresh() {
        textView.string = snapshotProvider().summary()
    }

    private func buildContent() {
        guard let window else {
            return
        }

        let contentView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 680, height: 520))
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        let scrollView = NSScrollView(frame: NSRect(x: 16, y: 64, width: 648, height: 440))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder

        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        let copyButton = NSButton(title: "Copy Diagnostics", target: self, action: #selector(copyDiagnosticsButtonPressed))
        copyButton.frame = NSRect(x: 270, y: 18, width: 124, height: 32)
        copyButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(copyButton)

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshButtonPressed))
        refreshButton.frame = NSRect(x: 400, y: 18, width: 86, height: 32)
        refreshButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(refreshButton)

        let openLogButton = NSButton(title: "Open Log", target: self, action: #selector(openLogButtonPressed))
        openLogButton.frame = NSRect(x: 492, y: 18, width: 86, height: 32)
        openLogButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(openLogButton)

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeButtonPressed))
        closeButton.frame = NSRect(x: 584, y: 18, width: 80, height: 32)
        closeButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(closeButton)
    }

    @objc private func refreshButtonPressed() {
        refresh()
    }

    @objc private func copyDiagnosticsButtonPressed() {
        refresh()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
    }

    @objc private func openLogButtonPressed() {
        onOpenLog()
    }

    @objc private func closeButtonPressed() {
        close()
    }
}
