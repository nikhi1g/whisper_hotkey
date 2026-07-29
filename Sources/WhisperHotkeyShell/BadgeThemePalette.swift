import AppKit
import WhisperHotkeyCore

struct BadgeThemePalette {
    let background: NSColor
    let primaryText: NSColor
    let waveform: NSColor
    let stopBackground: NSColor
    let stopForeground: NSColor
    let sendBackground: NSColor
    let sendForeground: NSColor
    let limitTrack: NSColor

    static func palette(for theme: BadgeTheme) -> Self {
        switch theme {
        case .githubDarkDimmed:
            return dark(background: 0x1F242C, text: 0xF0F3F6, accent: 0x87C7FF)
        case .midnightIndigo:
            return dark(background: 0x17182B, text: 0xF1F0FF, accent: 0xA7A4FF)
        case .graphite:
            return dark(background: 0x252525, text: 0xF2F2F2, accent: 0xB8C0CC)
        case .nord:
            return dark(background: 0x2E3440, text: 0xECEFF4, accent: 0x88C0D0)
        case .dracula:
            return dark(background: 0x282A36, text: 0xF8F8F2, accent: 0xBD93F9)
        case .solarizedDark:
            return dark(background: 0x073642, text: 0xEEE8D5, accent: 0x2AA198)
        case .forest:
            return dark(background: 0x18241D, text: 0xEEF7F0, accent: 0x7BC99B)
        case .ocean:
            return dark(background: 0x102A3A, text: 0xECF8FF, accent: 0x55C2E8)
        case .rosePine:
            return dark(background: 0x26233A, text: 0xE0DEF4, accent: 0xEBBCBA)
        case .lightFrost:
            return Self(
                background: color(0xECF2F8, alpha: 0.97),
                primaryText: color(0x172033),
                waveform: color(0x3178C6),
                stopBackground: color(0x172033, alpha: 0.08),
                stopForeground: color(0x34415A),
                sendBackground: color(0x172033),
                sendForeground: color(0xF8FBFF),
                limitTrack: color(0x172033, alpha: 0.10)
            )
        case .highContrast:
            return Self(
                background: color(0x050505, alpha: 0.98),
                primaryText: .white,
                waveform: color(0x66E3FF),
                stopBackground: color(0xFFFFFF, alpha: 0.15),
                stopForeground: .white,
                sendBackground: .white,
                sendForeground: .black,
                limitTrack: color(0xFFFFFF, alpha: 0.16)
            )
        }
    }

    private static func dark(
        background: Int,
        text: Int,
        accent: Int
    ) -> Self {
        Self(
            background: color(background, alpha: 0.95),
            primaryText: color(text),
            waveform: color(accent),
            stopBackground: color(text, alpha: 0.08),
            stopForeground: color(text, alpha: 0.88),
            sendBackground: color(text),
            sendForeground: color(background),
            limitTrack: color(text, alpha: 0.09)
        )
    }

    private static func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
