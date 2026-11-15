import AppKit
import SwiftUI

enum Theme {
    static let bg = dynamic(light: 0xFFFFFF, dark: 0x0B0B0B)
    static let panel = dynamic(light: 0xFAFAFA, dark: 0x111111)
    static let fg = dynamic(light: 0x0A0A0A, dark: 0xEDEDED)
    static let muted = dynamic(light: 0x6B6B6B, dark: 0x8A8A8A)
    static let rule = dynamic(light: 0xDDDDDD, dark: 0x2A2A2A)
    static let accent = dynamic(light: 0x2456E8, dark: 0x5B9DFF)
    static let canvas = NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x1A1A1A) : NSColor(hex: 0xE9E9E9) }
    static let highlight = NSColor(name: nil) {
        $0.isDark ? NSColor(hex: 0x5B9DFF, alpha: 0.35) : NSColor(hex: 0x2456E8, alpha: 0.22)
    }

    static let findHighlight = NSColor(name: nil) {
        $0.isDark ? NSColor(hex: 0xFFD60A, alpha: 0.35) : NSColor(hex: 0xFFD60A, alpha: 0.45)
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

/// `[ LABEL ]` flat button; inverts while pressed.
struct BracketButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let tint = prominent ? Theme.accent : Theme.fg
        configuration.label
            .font(Theme.mono(11, .medium))
            .tracking(0.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(configuration.isPressed ? Theme.bg : tint)
            .background(configuration.isPressed ? tint : .clear)
            .overlay(Rectangle().stroke(tint, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}
