import Foundation

/// Editor field definitions and the changed-fields diff.
public struct FormField: Sendable, Equatable, Identifiable {
    public enum FieldType: Sendable, Equatable {
        case text, date, number, select, checkbox
    }

    public let name: String
    public let label: String
    public let type: FieldType
    public var options: [String] = []
    /// Suggestions (combo box): "categories" or "currencies".
    public var suggestions: String? = nil
    public var wide = false
    public var hint: String? = nil

    public var id: String { name }
}

public enum EditForm {
    public static let regions = ["Germany", "European Union", "Outside of the European Union"]
    public static let currencies = ["EUR", "USD", "GBP", "CHF"]

    static let sharedHead: [FormField] = [
        FormField(name: "description", label: "Description", type: .text, wide: true),
        FormField(name: "date", label: "Date", type: .date),
    ]

    static let amounts: [FormField] = [
        FormField(name: "gross_amount", label: "Gross amount", type: .number, hint: "In the record currency"),
        FormField(name: "currency", label: "Currency", type: .text, suggestions: "currencies"),
        FormField(name: "currency_conversion_rate", label: "Conversion rate to EUR", type: .number,
                  hint: "Required for non-EUR"),
    ]

    public static func fields(_ kind: Kind) -> [FormField] {
        switch kind {
        case .expenses:
            return sharedHead + [FormField(name: "category", label: "Category", type: .text, suggestions: "categories")]
                + amounts + [
                    FormField(name: "deductible_amount", label: "Deductible amount (EUR)", type: .number),
                    FormField(name: "supplier_region", label: "Supplier region", type: .select, options: regions),
                    vatTreatment(kind),
                ]
        case .income:
            return sharedHead + [
                FormField(name: "payment_status", label: "Payment status", type: .select, options: ["Paid", "Unpaid"]),
                FormField(name: "payment_date", label: "Payment date", type: .date),
            ] + amounts + [
                FormField(name: "sale_type", label: "Sale type", type: .select,
                          options: ["Service", SortedMarkers.vatRefundSaleType]),
                FormField(name: "client_region", label: "Client region", type: .select, options: regions),
                FormField(name: "client_vat_number", label: "Client VAT number", type: .text),
                FormField(name: "client_is_private_person", label: "Client is a private person", type: .checkbox),
                vatTreatment(kind),
            ]
        }
    }

    /// The treatment's raw values as options; their English labels are in the string catalog under those keys.
    /// Empty ("—") leaves the treatment unset, so only the suggestion applies.
    static func vatTreatment(_ kind: Kind) -> FormField {
        FormField(name: "vat_treatment", label: "VAT treatment", type: .select,
                  options: VatTreatment.cases(for: kind).map(\.rawValue))
    }

    /// Form state: text per field (checkboxes as "true"/"false") plus VAT rows.
    public struct State: Sendable, Equatable {
        public var text: [String: String]
        public var flags: [String: Bool]
        public var vat: [VatRowInput]

        public init(text: [String: String] = [:], flags: [String: Bool] = [:], vat: [VatRowInput] = []) {
            self.text = text
            self.flags = flags
            self.vat = vat
        }
    }

    /// Initial values from a record ("" for null, like `String(v)` in the web form).
    public static func initialState(_ kind: Kind, values: RecordValues) -> State {
        var state = State()
        for field in fields(kind) {
            let value = values[field.name] ?? .null
            if field.type == .checkbox {
                state.flags[field.name] = value.bool ?? false
            } else if field.type == .number, field.name != "currency_conversion_rate", let d = value.decimal {
                state.text[field.name] = amountText(d)
            } else {
                state.text[field.name] = display(value)
            }
        }
        state.vat = (values["vat_rates"]?.vatRates ?? []).map {
            VatRowInput(rate: Money.plainString($0.rate), amount: amountText($0.amount))
        }
        return state
    }

    /// Defaults for a new record: today's date, EUR, and (for income) Unpaid / Service.
    public static func newState(_ kind: Kind, today: String) -> State {
        var values = RecordRules.defaults(kind)
        values["date"] = .date(today)
        var state = initialState(kind, values: values)
        state.vat = []
        return state
    }

    /// Amounts with at least two decimals ("1190.00"), never rounding away extra precision.
    static func amountText(_ d: Decimal) -> String {
        if Money.rounded(d) != d { return Money.plainString(d) }
        let p = Money.parts(d)
        return "\(p.negative ? "-" : "")\(p.whole.replacingOccurrences(of: ",", with: "")).\(p.cents)"
    }

    static func display(_ value: FieldValue) -> String {
        switch value {
        case .null: return ""
        case .text(let s), .date(let s): return s
        case .decimal(let d): return Money.plainString(d)
        case .int(let i): return String(i)
        case .bool(let b): return b ? "true" : "false"
        case .vatRates(let r): return VatRates.format(r)
        }
    }

    /// VAT rows as entered, dropping fully blank rows and accepting decimal commas.
    static func normalizedVat(_ rows: [VatRowInput]) -> [VatRowInput] {
        rows.filter { !$0.rate.trimmingCharacters(in: .whitespaces).isEmpty || !$0.amount.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { VatRowInput(rate: normalizeNumber($0.rate), amount: normalizeNumber($0.amount)) }
    }

    static func normalizeNumber(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    }

    /// Two VAT row lists are the same when they parse to the same numbers (or the same text when invalid).
    static func sameVat(_ a: [VatRowInput], _ b: [VatRowInput]) -> Bool {
        let key = { (rows: [VatRowInput]) in
            rows.map { row in
                [row.rate, row.amount].map { Money.parse($0).map(Money.plainString) ?? "?\($0)" }.joined(separator: "|")
            }
        }
        return key(normalizedVat(a)) == key(normalizedVat(b))
    }

    /// Only the fields the user changed, as editor input ("" → null, decimal commas → dots).
    public static func changedFields(_ kind: Kind, initial: State, current: State) -> [String: FieldInput] {
        var out: [String: FieldInput] = [:]
        for field in fields(kind) {
            if field.type == .checkbox {
                let before = initial.flags[field.name] ?? false
                let after = current.flags[field.name] ?? false
                if before != after { out[field.name] = .bool(after) }
                continue
            }
            let before = initial.text[field.name] ?? ""
            let after = current.text[field.name] ?? ""
            if before == after { continue }
            if after.trimmingCharacters(in: .whitespaces).isEmpty {
                out[field.name] = .null
            } else {
                out[field.name] = .text(field.type == .number ? normalizeNumber(after) : after)
            }
        }
        if !sameVat(initial.vat, current.vat) {
            out["vat_rates"] = .vatRates(normalizedVat(current.vat))
        }
        return out
    }

    /// All non-empty fields of a new record, as editor input.
    public static func createFields(_ kind: Kind, state: State) -> [String: FieldInput] {
        var out = changedFields(kind, initial: State(), current: state)
        out = out.filter { $0.value != .null }
        if out["vat_rates"] == nil { out["vat_rates"] = .vatRates([]) }
        return out
    }
}
