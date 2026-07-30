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
        case .tokyoNight:
            return dark(background: 0x1A1B26, text: 0xC0CAF5, accent: 0x7AA2F7)
        case .catppuccinMocha:
            return dark(background: 0x1E1E2E, text: 0xCDD6F4, accent: 0x89B4FA)
        case .gruvboxDark:
            return dark(background: 0x282828, text: 0xEBDBB2, accent: 0xFABD2F)
        case .monokai:
            return dark(background: 0x272822, text: 0xF8F8F2, accent: 0xA6E22E)
        case .lightFrost:
            return light(background: 0xECF2F8, text: 0x172033, accent: 0x3178C6)
        case .githubLight:
            return light(background: 0xF6F8FA, text: 0x1F2328, accent: 0x0969DA)
        case .solarizedLight:
            return light(background: 0xFDF6E3, text: 0x586E75, accent: 0x268BD2)
        case .nordSnow:
            return light(background: 0xECEFF4, text: 0x2E3440, accent: 0x5E81AC)
        case .rosePineDawn:
            return light(background: 0xFAF4ED, text: 0x575279, accent: 0xD7827E)
        case .paper:
            return light(background: 0xF7F3EA, text: 0x2F2B25, accent: 0x8C6A43)
        case .mint:
            return light(background: 0xEAF7F1, text: 0x173B32, accent: 0x238B73)
        case .sky:
            return light(background: 0xEAF4FB, text: 0x18324A, accent: 0x2680B8)
        case .lavender:
            return light(background: 0xF3EFFA, text: 0x352B4A, accent: 0x7C5CB8)
        case .highContrastLight:
            return light(background: 0xFFFFFF, text: 0x000000, accent: 0x005FCC)
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

    private static func light(
        background: Int,
        text: Int,
        accent: Int
    ) -> Self {
        Self(
            background: color(background, alpha: 0.98),
            primaryText: color(text),
            waveform: color(accent),
            stopBackground: color(text, alpha: 0.08),
            stopForeground: color(text, alpha: 0.82),
            sendBackground: color(text),
            sendForeground: color(background),
            limitTrack: color(text, alpha: 0.10)
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
