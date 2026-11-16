import AppKit
import SwiftUI

enum Theme {
    static let bg = dynamic(light: 0xFFFFFF, dark: 0x0B0B0B)
    static let panel = dynamic(light: 0xF7F7F7, dark: 0x121212)
    static let fg = dynamic(light: 0x111111, dark: 0xE8E8E8)
    static let muted = dynamic(light: 0x707070, dark: 0x8C8C8C)
    static let rule = dynamic(light: 0xDDDDDD, dark: 0x2A2A2A)
    /// Ink: emphasis comes from weight, not colour, so the panel never outshines the page.
    static let accent = dynamic(light: 0x111111, dark: 0xE8E8E8)
    static let canvas = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x1A1A1A) : NSColor(hex: 0xE9E9E9) }
    static let highlight = NSColor(name: nil) {
        $0.isDark ? NSColor(hex: 0xFFFFFF, alpha: 0.22) : NSColor(hex: 0x000000, alpha: 0.14)
    }

    static let findHighlight = NSColor(name: nil) {
        $0.isDark ? NSColor(hex: 0xFFD60A, alpha: 0.35) : NSColor(hex: 0xFFD60A, alpha: 0.35)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: dark) : NSColor(hex: light) })
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// `01 / WORD` style section label.
struct SectionLabel: View {
    let number: Int
    let title: String
    var body: some View {
        Text(String(format: "%02d / %@", number, title.uppercased()))
            .font(Theme.mono(10, .medium))
            .tracking(1)
            .foregroundStyle(Theme.muted)
    }
}

struct DashedRule: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: .init(x: 0, y: 0.5))
                p.addLine(to: .init(x: geo.size.width, y: 0.5))
            }
            .stroke(Theme.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .frame(height: 1)
    }
}

extension View {
    /// Pointing-hand cursor for anything clickable.
    func clickable() -> some View { pointerStyle(.link) }
}

/// `[ LABEL ]` flat button; prominent ones are filled with ink. Inverts while pressed.
struct BracketButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let filled = prominent != configuration.isPressed
        configuration.label
            .font(Theme.mono(11, .medium))
            .tracking(0.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(filled ? Theme.bg : Theme.fg)
            .background(filled ? Theme.fg : .clear)
            .overlay(Rectangle().stroke(Theme.fg, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .clickable()
    }
}
