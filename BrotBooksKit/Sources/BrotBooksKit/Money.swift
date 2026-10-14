import Foundation

/// EUR money helpers. Amounts arrive as strings ("1234.56") and are handled as `Decimal` throughout.
public enum Money {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Parses a plain decimal amount ("1234.56", "-302.18", "0") into a Decimal. Returns nil for empty or invalid text.
    public static func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil
        else { return nil }
        return Decimal(string: trimmed, locale: posix)
    }

    /// Parses user input, accepting a decimal comma ("11,40") like the web form does.
    public static func parseInput(_ text: String) -> Decimal? {
        parse(text.replacingOccurrences(of: ",", with: "."))
    }

    /// Exact, locale-independent text for a Decimal ("2731.25", "19", "-0.5").
    public static func plainString(_ value: Decimal) -> String {
        var v = value
        return NSDecimalString(&v, posix)
    }

    /// Rounds to `scale` fraction digits. `.plain` is half away from zero; `.bankers` is half-even.
    public static func rounded(_ value: Decimal, scale: Int = 2, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, mode)
        return result
    }

    /// Truncates toward zero to `scale` fraction digits.
    public static func truncated(_ value: Decimal, scale: Int = 2) -> Decimal {
        rounded(value, scale: scale, mode: value < 0 ? .up : .down)
    }

    /// Storage form for CloudKit-backed models: exact decimal text, nil stays nil.
    public static func store(_ value: Decimal?) -> String? {
        value.map(plainString)
    }

    /// Absolute value split for Mercury-style display: "€", "127,837", "05".
    public struct Parts: Equatable, Sendable {
        public let negative: Bool
        public let symbol: String
        public let whole: String
        public let cents: String
    }

    public static func parts(_ value: Decimal) -> Parts {
        let r = rounded(value)
        let negative = r < 0
        let absolute = negative ? -r : r
        let text = plainString(rounded(absolute))
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        let integer = String(pieces[0])
        var cents = pieces.count > 1 ? String(pieces[1]) : ""
        cents = String((cents + "00").prefix(2))
        return Parts(negative: negative, symbol: "€", whole: group(integer), cents: cents)
    }

    /// "€127,837.05"; negatives get a leading "−" (U+2212); `signed` adds "+" to positives.
    public static func format(_ value: Decimal?, signed: Bool = false) -> String {
        let p = parts(value ?? 0)
        let text = "\(p.symbol)\(p.whole).\(p.cents)"
        if p.negative { return "−\(text)" }
        if signed && (value ?? 0) > 0 { return "+\(text)" }
        return text
    }

    /// Original-currency amount for non-EUR rows, e.g. "USD 800.00".
    public static func formatForeign(_ value: Decimal, currency: String) -> String {
        let p = parts(value)
        return "\(currency) \(p.negative ? "-" : "")\(p.whole.replacingOccurrences(of: ",", with: "")).\(p.cents)"
    }

    private static func group(_ digits: String) -> String {
        var out: [Character] = []
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return String(out.reversed())
    }
}
