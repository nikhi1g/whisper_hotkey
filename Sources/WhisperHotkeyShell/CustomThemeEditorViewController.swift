import AppKit
import WhisperHotkeyCore

@MainActor
final class CustomThemeEditorViewController:
    NSViewController,
    NSTextFieldDelegate
{
    typealias SaveHandler = (CustomBadgeTheme) -> Void
    static let contentHeight: CGFloat = 460

    private let themeID: UUID
    private let onSave: SaveHandler
    private let onCancel: () -> Void
    private let nameField = NSTextField()
    private let modeControl = NSSegmentedControl(
        labels: ["Dark", "Light"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let backgroundWell = NSColorWell()
    private let backgroundHex = NSTextField()
    private let textWell = NSColorWell()
    private let textHex = NSTextField()
    private let accentWell = NSColorWell()
    private let accentHex = NSTextField()
    private let preview = CustomThemePreviewView()
    private let saveButton = NSButton(
        title: "Save Preset",
        target: nil,
        action: nil
    )

    init(
        theme: CustomBadgeTheme?,
        onSave: @escaping SaveHandler,
        onCancel: @escaping () -> Void = {}
    ) {
        let initial = theme ?? CustomBadgeTheme(
            name: "My Theme",
            mode: .dark,
            backgroundHex: "#1F242C",
            textHex: "#F0F3F6",
            accentHex: "#87C7FF"
        )!
        themeID = initial.id
        self.onSave = onSave
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)

        nameField.stringValue = initial.name
        modeControl.selectedSegment = initial.mode == .dark ? 0 : 1
        set(initial.backgroundHex, well: backgroundWell, field: backgroundHex)
        set(initial.textHex, well: textWell, field: textHex)
        set(initial.accentHex, well: accentWell, field: accentHex)
        updatePreviewAndValidation()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = makeContentView()
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let title = NSTextField(labelWithString: "CUSTOM THEME")
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(
            wrappingLabelWithString:
                "Choose three colors. The remaining HUD colors are derived automatically."
        )
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)

        let form = NSGridView()
        form.columnSpacing = 14
        form.rowSpacing = 12
        form.addRow(with: [
            makeLabel("Preset name"),
            nameField,
        ])
        form.addRow(with: [
            makeLabel("Appearance"),
            modeControl,
        ])
        form.addRow(with: [
            makeLabel("Background"),
            colorControls(well: backgroundWell, field: backgroundHex),
        ])
        form.addRow(with: [
            makeLabel("Text"),
            colorControls(well: textWell, field: textHex),
        ])
        form.addRow(with: [
            makeLabel("Accent"),
            colorControls(well: accentWell, field: accentHex),
        ])
        form.column(at: 0).width = 104
        form.column(at: 1).width = 340
        stack.addArrangedSubview(form)

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.setAccessibilityLabel("Live custom theme preview")
        stack.addArrangedSubview(preview)

        let cancel = NSButton(
            title: "Cancel",
            target: self,
            action: #selector(cancelEditing)
        )
        cancel.keyEquivalent = "\u{1b}"
        saveButton.target = self
        saveButton.action = #selector(saveTheme)
        saveButton.keyEquivalent = "\r"
        let buttonSpacer = NSView()
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [buttonSpacer, cancel, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        stack.addArrangedSubview(buttons)

        nameField.delegate = self
        nameField.placeholderString = "Preset name"
        nameField.setAccessibilityLabel("Preset name")
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        configure(
            backgroundWell,
            field: backgroundHex,
            action: #selector(backgroundColorChanged)
        )
        configure(
            textWell,
            field: textHex,
            action: #selector(textColorChanged)
        )
        configure(
            accentWell,
            field: accentHex,
            action: #selector(accentColorChanged)
        )

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            form.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.heightAnchor.constraint(equalToConstant: 76),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return root
    }

    private func makeLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        return label
    }

    private func colorControls(
        well: NSColorWell,
        field: NSTextField
    ) -> NSStackView {
        well.translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [well, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: 44),
            well.heightAnchor.constraint(equalToConstant: 28),
            field.widthAnchor.constraint(equalToConstant: 112),
        ])
        return row
    }

    private func configure(
        _ well: NSColorWell,
        field: NSTextField,
        action: Selector
    ) {
        well.target = self
        well.action = action
        field.delegate = self
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.placeholderString = "#RRGGBB"
    }

    private func set(
        _ hex: String,
        well: NSColorWell,
        field: NSTextField
    ) {
        field.stringValue = hex
        well.color = Self.color(hex)
    }

    @objc private func backgroundColorChanged() {
        sync(well: backgroundWell, field: backgroundHex)
    }

    @objc private func textColorChanged() {
        sync(well: textWell, field: textHex)
    }

    @objc private func accentColorChanged() {
        sync(well: accentWell, field: accentHex)
    }

    @objc private func modeChanged() {
        updatePreviewAndValidation()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return
        }
        if field === backgroundHex {
            sync(field: field, well: backgroundWell)
        } else if field === textHex {
            sync(field: field, well: textWell)
        } else if field === accentHex {
            sync(field: field, well: accentWell)
        } else {
            updatePreviewAndValidation()
        }
    }

    private func sync(well: NSColorWell, field: NSTextField) {
        field.stringValue = Self.hex(well.color)
        updatePreviewAndValidation()
    }

    private func sync(field: NSTextField, well: NSColorWell) {
        guard let normalized = CustomBadgeTheme.normalizeHex(
            field.stringValue
        ) else {
            updatePreviewAndValidation()
            return
        }
        well.color = Self.color(normalized)
        updatePreviewAndValidation()
    }

    private var draft: CustomBadgeTheme? {
        CustomBadgeTheme(
            id: themeID,
            name: nameField.stringValue,
            mode: modeControl.selectedSegment == 1 ? .light : .dark,
            backgroundHex: backgroundHex.stringValue,
            textHex: textHex.stringValue,
            accentHex: accentHex.stringValue
        )
    }

    private func updatePreviewAndValidation() {
        let fields = [backgroundHex, textHex, accentHex]
        for field in fields {
            field.textColor =
                CustomBadgeTheme.normalizeHex(field.stringValue) == nil
                ? .systemRed
                : .labelColor
        }
        guard let draft else {
            saveButton.isEnabled = false
            return
        }
        saveButton.isEnabled = true
        preview.apply(theme: draft)
    }

    @objc private func saveTheme() {
        guard let draft else {
            NSSound.beep()
            return
        }
        onSave(draft)
    }

    @objc private func cancelEditing() {
        onCancel()
    }

    private static func color(_ hex: String) -> NSColor {
        let digits = hex.trimmingCharacters(
            in: CharacterSet(charactersIn: "#")
        )
        let value = Int(digits, radix: 16) ?? 0
        return NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func hex(_ color: NSColor) -> String {
        let converted = color.usingColorSpace(.sRGB) ?? color
        return String(
            format: "#%02X%02X%02X",
            Int(round(converted.redComponent * 255)),
            Int(round(converted.greenComponent * 255)),
            Int(round(converted.blueComponent * 255))
        )
    }

    var previewThemeForTesting: CustomBadgeTheme? {
        preview.themeForTesting
    }

    var saveIsEnabledForTesting: Bool {
        saveButton.isEnabled
    }

    var controlsFitWindowForTesting: Bool {
        loadViewIfNeeded()
        let frame = CGRect(
            x: 0,
            y: 0,
            width: 556,
            height: Self.contentHeight
        )
        let layoutWindow = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        layoutWindow.contentViewController = self
        view.frame = frame
        view.layoutSubtreeIfNeeded()
        let containmentBounds = view.bounds.insetBy(dx: -0.5, dy: -0.5)
        let controlsFit = [
            nameField,
            modeControl,
            backgroundWell,
            backgroundHex,
            textWell,
            textHex,
            accentWell,
            accentHex,
            preview,
            saveButton,
        ].allSatisfy { view in
            let frame = view.convert(view.bounds, to: self.view)
            return frame.width > 0
                && frame.height > 0
                && containmentBounds.contains(frame)
        }
        return withExtendedLifetime(layoutWindow) { controlsFit }
    }

    func setValuesForTesting(
        name: String,
        mode: BadgeThemeMode,
        background: String,
        text: String,
        accent: String
    ) {
        nameField.stringValue = name
        modeControl.selectedSegment = mode == .dark ? 0 : 1
        backgroundHex.stringValue = background
        textHex.stringValue = text
        accentHex.stringValue = accent
        updatePreviewAndValidation()
    }

    func saveForTesting() {
        saveTheme()
    }

    var previewShowsActivityOriginForTesting: Bool {
        preview.showsActivityOriginForTesting
    }
}

@MainActor
private final class CustomThemePreviewView: NSView {
    private(set) var themeForTesting: CustomBadgeTheme?
    private(set) var showsActivityOriginForTesting = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: CustomBadgeTheme) {
        themeForTesting = theme
        showsActivityOriginForTesting = true
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let theme = themeForTesting else {
            return
        }
        let palette = BadgeThemePalette.palette(for: .custom(theme))
        let capsule = bounds.insetBy(dx: 8, dy: 8)
        palette.background.setFill()
        NSBezierPath(
            roundedRect: capsule,
            xRadius: capsule.height / 2,
            yRadius: capsule.height / 2
        ).fill()

        let originSize = ActivityOriginStyle.size
        palette.waveform.setFill()
        NSBezierPath(
            rect: NSRect(
                x: capsule.midX - originSize / 2,
                y: capsule.maxY - CapsuleActivityIndicatorStyle.inset
                    - originSize / 2,
                width: originSize,
                height: originSize
            )
        ).fill()

        palette.waveform.setFill()
        let heights: [CGFloat] = [12, 22, 18, 28, 16, 24, 14, 20]
        for (index, height) in heights.enumerated() {
            let rect = NSRect(
                x: capsule.minX + 22 + CGFloat(index) * 6,
                y: capsule.midY - height / 2,
                width: 3,
                height: height
            )
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }

        let timer = NSAttributedString(
            string: "0:13",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: 14,
                    weight: .semibold
                ),
                .foregroundColor: palette.primaryText,
            ]
        )
        timer.draw(
            at: CGPoint(
                x: capsule.minX + 90,
                y: capsule.midY - timer.size().height / 2
            )
        )

        palette.stopBackground.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: capsule.maxX - 92,
                y: capsule.midY - 20,
                width: 40,
                height: 40
            )
        ).fill()
        palette.stopForeground.setFill()
        let stopBounds = NSRect(
            x: capsule.maxX - 92,
            y: capsule.midY - 20,
            width: 40,
            height: 40
        )
        let stopGeometry = BadgeActionSymbolGeometry(in: stopBounds)
        NSBezierPath(
            roundedRect: stopGeometry.stopRect,
            xRadius: 2,
            yRadius: 2
        ).fill()

        palette.sendBackground.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: capsule.maxX - 46,
                y: capsule.midY - 20,
                width: 40,
                height: 40
            )
        ).fill()
        palette.sendForeground.setStroke()
        let sendBounds = NSRect(
            x: capsule.maxX - 46,
            y: capsule.midY - 20,
            width: 40,
            height: 40
        )
        let sendGeometry = BadgeActionSymbolGeometry(in: sendBounds)
        let arrow = NSBezierPath()
        arrow.lineWidth = sendGeometry.arrowLineWidth
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.move(to: sendGeometry.arrowBottom)
        arrow.line(to: sendGeometry.arrowTip)
        arrow.move(to: sendGeometry.arrowLeft)
        arrow.line(to: sendGeometry.arrowTip)
        arrow.line(to: sendGeometry.arrowRight)
        arrow.stroke()
    }
}
