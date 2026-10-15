import Foundation

/// How much of an expense's VAT is deductible as input tax (Vorsteuer). This differs from the income-tax
/// deductible share: business meals are 70 % deductible for income tax but their VAT is deductible in full.
public enum VorsteuerSharePolicy: String, Sendable, Hashable, Codable, CaseIterable {
    /// All of the VAT.
    case full
    /// The record's income-tax share (`DeductibleShare`), for mixed business and private use.
    case followsDeductibleShare
    /// None of the VAT.
    case none
}

/// Expense categories → Vorsteuer share policy. Categories are the user's own free text, so rules match
/// keywords: a category matches a rule when one of the rule's keywords appears in it as a sequence of whole
/// words (case- and diacritic-insensitive); a keyword ending in `*` matches any word starting with it
/// ("telefon*" matches "Telefonkosten"). The first matching rule wins; `fallback` applies otherwise.
public struct VorsteuerShareRules: Sendable, Hashable, Codable {
    public struct Rule: Sendable, Hashable, Codable {
        public var keywords: [String]
        public var policy: VorsteuerSharePolicy

        public init(_ policy: VorsteuerSharePolicy, _ keywords: [String]) {
            self.keywords = keywords
            self.policy = policy
        }
    }

    public var rules: [Rule]
    /// The policy for categories no rule matches.
    public var fallback: VorsteuerSharePolicy
    /// The policy for records flagged `is_home_office`, ahead of the category rules; nil to go by category only.
    public var homeOffice: VorsteuerSharePolicy?

    public init(rules: [Rule], fallback: VorsteuerSharePolicy = .full, homeOffice: VorsteuerSharePolicy? = nil) {
        self.rules = rules
        self.fallback = fallback
        self.homeOffice = homeOffice
    }

    /// Business meals in full (§15 UStG has no 70 % cap), gifts not at all (§15(1a) UStG), mixed-use items
    /// (phone, internet, car, home office) by the income-tax share, everything else in full.
    public static let `default` = VorsteuerShareRules(
        rules: [
            Rule(.full, ["business meal*", "meal*", "bewirtung*", "entertainment", "restaurant*"]),
            Rule(.none, ["gift*", "geschenk*", "präsent*"]),
            Rule(.followsDeductibleShare, [
                "phone*", "telephone*", "mobile*", "telefon*", "handy*", "mobilfunk*", "internet*",
                "car", "cars", "vehicle*", "kfz*", "auto", "autos", "pkw*", "fuel", "petrol", "benzin*", "tank*",
                "home office", "homeoffice", "arbeitszimmer*",
            ]),
        ],
        fallback: .full,
        homeOffice: .followsDeductibleShare
    )

    /// The policy for an expense `category`.
    public func policy(forCategory category: String?) -> VorsteuerSharePolicy {
        let words = Self.words(category ?? "")
        guard !words.isEmpty else { return fallback }
        for rule in rules where rule.keywords.contains(where: { Self.matches(keyword: $0, words: words) }) {
            return rule.policy
        }
        return fallback
    }

    /// The policy for an expense's values: the home-office policy for home-office records, else by category.
    public func policy(for values: RecordValues) -> VorsteuerSharePolicy {
        if let homeOffice, values["is_home_office"]?.bool == true { return homeOffice }
        return policy(forCategory: values["category"]?.text)
    }

    /// The share (0…1) of an expense's VAT that is deductible as input tax.
    public func share(for values: RecordValues) -> Decimal {
        switch policy(for: values) {
        case .full: return 1
        case .followsDeductibleShare: return DeductibleShare.of(values)
        case .none: return 0
        }
    }

    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber && $0 != "*" }
            .map(String.init)
    }

    static func matches(keyword: String, words: [String]) -> Bool {
        let pattern = Self.words(keyword)
        guard !pattern.isEmpty, pattern.count <= words.count else { return false }
        return (0...(words.count - pattern.count)).contains { start in
            pattern.enumerated().allSatisfy { offset, token in
                let word = words[start + offset]
                return token.hasSuffix("*") ? word.hasPrefix(token.dropLast()) : word == token
            }
        }
    }
}
