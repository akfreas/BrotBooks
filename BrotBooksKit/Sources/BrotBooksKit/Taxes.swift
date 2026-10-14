import Foundation

/// German income tax (§32a EStG) and solidarity surcharge for a single filer.
/// Tariffs are the final, as-amended versions per assessment year; later years use the newest tariff.
public struct Tariff: Sendable, Equatable {
    public let basicAllowance: Int      // Grundfreibetrag: zone 1 ends here
    public let zone2End: Int
    public let zone2Factor: Double      // (factor * y + 1400) * y
    public let zone3End: Int
    public let zone3Factor: Double      // (factor * z + 2397) * z + zone3Constant
    public let zone3Constant: Double
    public let zone4End: Int
    public let zone4Deduction: Double   // 0.42 * x - deduction
    public let zone5Deduction: Double   // 0.45 * x - deduction
    public let soliThreshold: Int       // Freigrenze for the solidarity surcharge
}

public enum GermanTax {
    public static let tariffs: [Int: Tariff] = [
        2021: Tariff(basicAllowance: 9744, zone2End: 14753, zone2Factor: 995.21, zone3End: 57918, zone3Factor: 208.85,
                     zone3Constant: 950.96, zone4End: 274612, zone4Deduction: 9136.63, zone5Deduction: 17374.99, soliThreshold: 16956),
        2022: Tariff(basicAllowance: 10347, zone2End: 14926, zone2Factor: 1088.67, zone3End: 58596, zone3Factor: 206.43,
                     zone3Constant: 869.32, zone4End: 277825, zone4Deduction: 9336.45, zone5Deduction: 17671.20, soliThreshold: 16956),
        2023: Tariff(basicAllowance: 10908, zone2End: 15999, zone2Factor: 979.18, zone3End: 62809, zone3Factor: 192.59,
                     zone3Constant: 966.53, zone4End: 277825, zone4Deduction: 9972.98, zone5Deduction: 18307.73, soliThreshold: 17543),
        2024: Tariff(basicAllowance: 11784, zone2End: 17005, zone2Factor: 954.80, zone3End: 66760, zone3Factor: 181.19,
                     zone3Constant: 991.21, zone4End: 277825, zone4Deduction: 10636.31, zone5Deduction: 18971.06, soliThreshold: 18130),
        2025: Tariff(basicAllowance: 12096, zone2End: 17443, zone2Factor: 932.30, zone3End: 68480, zone3Factor: 176.64,
                     zone3Constant: 1015.13, zone4End: 277825, zone4Deduction: 10911.92, zone5Deduction: 19246.67, soliThreshold: 19950),
        2026: Tariff(basicAllowance: 12348, zone2End: 17799, zone2Factor: 914.51, zone3End: 69878, zone3Factor: 173.10,
                     zone3Constant: 1034.87, zone4End: 277825, zone4Deduction: 11135.63, zone5Deduction: 19470.38, soliThreshold: 20350),
    ]

    /// The tariff year applied for an assessment year (clamped to known tariffs).
    public static func tariffYear(_ year: Int) -> Int {
        min(max(year, tariffs.keys.min()!), tariffs.keys.max()!)
    }

    /// Income tax in whole euros for a single filer (§32a EStG).
    public static func incomeTax(_ taxableIncome: Decimal, year: Int) -> Int {
        let t = tariffs[tariffYear(year)]!
        let floored = Money.rounded(max(taxableIncome, 0), scale: 0, mode: .down)
        let x = NSDecimalNumber(decimal: floored).intValue
        let xd = Double(x)
        let tax: Double
        if x <= t.basicAllowance {
            tax = 0
        } else if x <= t.zone2End {
            let y = Double(x - t.basicAllowance) / 10000
            tax = (t.zone2Factor * y + 1400) * y
        } else if x <= t.zone3End {
            let z = Double(x - t.zone2End) / 10000
            tax = (t.zone3Factor * z + 2397) * z + t.zone3Constant
        } else if x <= t.zone4End {
            tax = 0.42 * xd - t.zone4Deduction
        } else {
            tax = 0.45 * xd - t.zone5Deduction
        }
        return Int(tax.rounded(.down))
    }

    public static func incomeTax(_ taxableIncome: Int, year: Int) -> Int {
        incomeTax(Decimal(taxableIncome), year: year)
    }

    /// Solidaritätszuschlag: 0 up to the Freigrenze, then the lower of 5.5 % of the tax and
    /// 11.9 % of the excess over the Freigrenze (Milderungszone), truncated to cents.
    public static func solidaritySurcharge(_ tax: Decimal, year: Int) -> Decimal {
        let threshold = Decimal(tariffs[tariffYear(year)]!.soliThreshold)
        if tax <= threshold { return 0 }
        let soli = min(Decimal(string: "0.055")! * tax, Decimal(string: "0.119")! * (tax - threshold))
        return Money.truncated(soli)
    }

    public static let assumptions = [
        "German taxes for a single filer; the invoice date decides which year a record counts in.",
        "Taxable profit = net income − deductible net expenses; VAT payments and refunds are excluded.",
        "No other income, deductions, tax prepayments, trade tax or church tax; depreciation is not modeled.",
        "VAT outstanding subtracts VAT payments to the tax office and adds refunds recorded in the same period.",
    ]
}

public struct TaxEstimate: Sendable, Equatable {
    public struct VAT: Sendable, Equatable {
        public var outputVat, inputVat, liability, payments, refunds, outstanding: Decimal
    }

    public struct IncomeTax: Sendable, Equatable {
        public var incomeNet, deductibleExpensesNet, taxableProfit, incomeTax, solidaritySurcharge, total: Decimal
        public var tariffYear: Int
    }

    public var year: Int
    public var dateFrom: String
    public var dateTo: String
    public var vat: VAT
    public var incomeTax: IncomeTax
    public var totalDue: Decimal
    public var assumptions: [String]
}

extension Reports {
    /// Estimated German VAT and income tax still to pay for a year, or Jan 1 → `dateTo`.
    public static func taxes(_ entries: [LedgerEntry], year: Int, dateTo: String? = nil) throws -> TaxEstimate {
        let start = ISODate.make(year, 1, 1)
        var end = ISODate.make(year, 12, 31)
        if let dateTo {
            guard ISODate.isValid(dateTo), dateTo >= start, dateTo <= end else {
                throw ValidationError("date_to must fall within \(year)")
            }
            end = dateTo
        }
        var outputVat: Decimal = 0, incomeNet: Decimal = 0, refunds: Decimal = 0
        var inputVat: Decimal = 0, deductibleNet: Decimal = 0, payments: Decimal = 0
        for e in entries where e.within(start, end) {
            switch e.kind {
            case .income where e.isVatRefund:
                refunds += e.convertedGross ?? 0
            case .income:
                outputVat += e.vat ?? 0
                incomeNet += e.net ?? 0
            case .expenses where e.isVatPayment:
                payments += e.convertedGross ?? 0
            case .expenses:
                inputVat += e.vat ?? 0
                deductibleNet += deductiblePart(e)
            }
        }
        deductibleNet = Money.rounded(deductibleNet)
        let liability = outputVat - inputVat
        let outstanding = liability - payments + refunds
        let profit = incomeNet - deductibleNet
        let tax = Decimal(GermanTax.incomeTax(profit, year: year))
        let soli = GermanTax.solidaritySurcharge(tax, year: year)
        return TaxEstimate(
            year: year, dateFrom: start, dateTo: end,
            vat: .init(outputVat: outputVat, inputVat: inputVat, liability: liability, payments: payments,
                       refunds: refunds, outstanding: outstanding),
            incomeTax: .init(incomeNet: incomeNet, deductibleExpensesNet: deductibleNet, taxableProfit: profit,
                             incomeTax: tax, solidaritySurcharge: soli, total: tax + soli,
                             tariffYear: GermanTax.tariffYear(year)),
            totalDue: outstanding + tax + soli,
            assumptions: GermanTax.assumptions)
    }

    /// `net × deductible / gross`, so partly deductible items (business meals) count partially.
    static func deductiblePart(_ e: LedgerEntry) -> Decimal {
        guard let net = e.net else { return 0 }
        guard let deductible = e.deductible, let gross = e.convertedGross, gross != 0 else { return net }
        return net * deductible / gross
    }
}

