import SwiftUI
import BrotBooksKit

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

/// Mercury-inspired palette, adapted to light and dark appearance.
enum Theme {
    static let accent = Color(light: 0x5266EB, dark: 0x7D8CF5)
    static let moneyIn = Color(light: 0x188A50, dark: 0x3CC27F)
    static let bad = Color(light: 0xC2410C, dark: 0xF5865B)
    static let amber = Color(light: 0x9A6B00, dark: 0xF2C14E)
    static let avatar = Color(light: 0xECEEFD, dark: 0x2D3160)
    static let avatarText = Color(light: 0x4250C7, dark: 0xC5CCFF)

    #if os(macOS)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color(nsColor: .separatorColor)
    #else
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let hairline = Color(uiColor: .separator)
    #endif

    static let cardRadius: CGFloat = 12
}

extension Color {
    /// A color that switches between two hex values with the system appearance.
    init(light: UInt32, dark: UInt32) {
        func make(_ hex: UInt32) -> PlatformColor {
            PlatformColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                          blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? make(dark) : make(light)
        })
        #else
        self.init(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? make(dark) : make(light) })
        #endif
    }
}

/// White (or elevated dark) card with a hairline border.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.hairline.opacity(0.7), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }
}

extension View {
    func card(padding: CGFloat = 20) -> some View { modifier(CardStyle(padding: padding)) }
}

/// Small uppercase, letter-spaced section label.
struct SectionLabel: View {
    let text: Text

    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim: String) { text = Text(verbatim) }
    init(_ text: Text) { self.text = text }

    var body: some View {
        text
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.9)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Muted status pill.
struct Pill: View {
    let text: Text
    var tint: Color = .secondary

    var body: some View {
        text
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Large Mercury-style amount: "€127,837" with raised, smaller cents.
struct AmountText: View {
    let value: Decimal
    var size: CGFloat = 38
    var color: Color = .primary

    @ScaledMetric private var scale: CGFloat = 1

    var body: some View {
        let p = Money.parts(value)
        let big = size * scale
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if p.negative { Text(verbatim: "−").font(.system(size: big, weight: .medium)) }
            Text(verbatim: p.symbol).font(.system(size: big * 0.62, weight: .medium)).baselineOffset(big * 0.28)
            Text(verbatim: p.whole).font(.system(size: big, weight: .medium))
            Text(verbatim: ".\(p.cents)").font(.system(size: big * 0.5, weight: .medium)).baselineOffset(big * 0.36)
                .foregroundStyle(color.opacity(0.75))
        }
        .monospacedDigit()
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Money.format(value)))
    }
}

/// Initials in a lavender circle.
struct Avatar: View {
    let text: String?
    var size: CGFloat = 32

    var body: some View {
        Text(verbatim: DashboardMath.initials(text))
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(Theme.avatarText)
            .frame(width: size, height: size)
            .background(Theme.avatar, in: Circle())
            .accessibilityHidden(true)
    }
}

enum Dates {
    private static func format(_ iso: String, _ style: Date.FormatStyle) -> String {
        guard let c = ISODate.components(iso) else { return iso }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day))!
        var s = style
        s.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(s)
    }

    static func short(_ iso: String) -> String { format(iso, .dateTime.month(.abbreviated).day()) }
    static func long(_ iso: String) -> String { format(iso, .dateTime.month(.abbreviated).day().year()) }
    static func month(_ iso: String) -> String { format(iso, .dateTime.month(.abbreviated)) }

    static func date(_ iso: String) -> Date? {
        guard let c = ISODate.components(iso) else { return nil }
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: c.year, month: c.month, day: c.day))
    }

    static func iso(_ date: Date) -> String { ISODate.today(date) }
}
