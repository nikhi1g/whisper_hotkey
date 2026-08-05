import AppKit
import Foundation
import WhisperHotkeyCore

/// A small determinate progress window for long transfers.
///
/// Shared by the on-demand model download and the in-app update install, so
/// both report the same way instead of appearing to hang.
@MainActor
public final class ModelDownloadProgressPanel: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let progress = NSProgressIndicator()
    private let detail = NSTextField(labelWithString: "Starting…")
    private let onCancel: (() -> Void)?
    private var totalByteCount: Int64?

    public init(
        title: String,
        totalByteCount: Int64?,
        onCancel: (() -> Void)?
    ) {
        self.totalByteCount = totalByteCount
        self.onCancel = onCancel
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 118),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.title = title
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.delegate = self

        progress.isIndeterminate = totalByteCount == nil
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = 0
        progress.style = .bar
        progress.controlSize = .regular
        if totalByteCount == nil {
            progress.startAnimation(nil)
        }

        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [progress, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(
            top: 18,
            left: 20,
            bottom: 18,
            right: 20
        )
        stack.translatesAutoresizingMaskIntoConstraints = false

        if onCancel != nil {
            let cancel = NSButton(
                title: "Cancel",
                target: self,
                action: #selector(cancelPressed)
            )
            cancel.bezelStyle = .rounded
            let row = NSStackView(views: [cancel])
            row.orientation = .horizontal
            row.alignment = .centerY
            stack.addArrangedSubview(row)
        }

        panel.contentView = stack
        NSLayoutConstraint.activate([
            progress.widthAnchor.constraint(equalToConstant: 340),
        ])
    }

    public func show() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func update(completedByteCount: Int64, totalByteCount: Int64?) {
        if let totalByteCount, totalByteCount > 0 {
            self.totalByteCount = totalByteCount
        }
        guard let total = self.totalByteCount, total > 0 else {
            detail.stringValue = ModelDownloadCatalog.humanReadableSize(
                completedByteCount
            )
            return
        }
        if progress.isIndeterminate {
            progress.stopAnimation(nil)
            progress.isIndeterminate = false
        }
        let fraction = min(1, Double(completedByteCount) / Double(total))
        progress.doubleValue = fraction
        let done = ModelDownloadCatalog.humanReadableSize(completedByteCount)
        let all = ModelDownloadCatalog.humanReadableSize(total)
        detail.stringValue = "\(done) of \(all)  ·  \(Int(fraction * 100))%"
    }

    /// Switches to an untimed phase, such as checksum verification, where a
    /// percentage would be misleading.
    public func showIndeterminate(_ message: String) {
        totalByteCount = nil
        if !progress.isIndeterminate {
            progress.isIndeterminate = true
            progress.startAnimation(nil)
        }
        detail.stringValue = message
    }

    public func close() {
        progress.stopAnimation(nil)
        panel.delegate = nil
        panel.close()
    }

    @objc private func cancelPressed() {
        onCancel?()
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCancel?()
        return onCancel == nil
    }
}
