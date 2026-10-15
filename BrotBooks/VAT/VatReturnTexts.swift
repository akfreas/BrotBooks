#if os(macOS)
import BrotBooksKit
import EricKit
import SwiftUI

/// User-facing English text for the VAT returns screen: titles, statuses, warnings and Kennzahl names.
enum VatReturnTexts {
    static func title(_ item: VatReturnItem) -> Text {
        switch item.type {
        case .ustva(let period): return periodTitle(period)
        case .sondervorauszahlung(let year): return Text("Sondervorauszahlung \(String(year))")
        case .dauerfristverlaengerung(let year): return Text("Dauerfristverlängerung application \(String(year))")
        case .zm(let period): return Text("ZM \(periodTitleString(period))")
        }
    }

    static func titleString(_ item: VatReturnItem) -> String {
        switch item.type {
        case .ustva(let period): return periodTitleString(period)
        case .sondervorauszahlung(let year): return String(localized: "Sondervorauszahlung \(String(year))")
        case .dauerfristverlaengerung(let year):
            return String(localized: "Dauerfristverlängerung application \(String(year))")
        case .zm(let period): return String(localized: "ZM \(periodTitleString(period))")
        }
    }

    static func periodTitle(_ period: VatPeriod) -> Text { Text(verbatim: periodTitleString(period)) }

    static func periodTitleString(_ period: VatPeriod) -> String {
        switch period.length {
        case .month:
            let date = Dates.date(period.start) ?? Date()
            return date.formatted(.dateTime.month(.wide).year())
        case .quarter:
            return String(localized: "Q\(period.index) \(String(period.year))")
        }
    }

    /// "UStVA" or the yearly return's kind, under the title.
    static func subtitle(_ item: VatReturnItem) -> Text {
        switch item.type {
        case .ustva(let period): return period.length == .month ? Text("Monthly UStVA") : Text("Quarterly UStVA")
        case .sondervorauszahlung: return Text("Special advance payment")
        case .dauerfristverlaengerung: return Text("Extension of the filing deadline")
        case .zm(let period):
            return period.length == .month ? Text("Monthly EC sales list (ZM)") : Text("Quarterly EC sales list (ZM)")
        }
    }

    static func status(_ status: VatReturnStatus) -> Text {
        switch status {
        case .notDue: return Text("Not due")
        case .dueIn(0): return Text("Due today")
        case .dueIn(let days): return Text("Due in ^[\(days) day](inflect: true)")
        case .overdue: return Text("Overdue")
        case .uncertain: return Text("Check status")
        case .filedElsewhere: return Text("Filed elsewhere")
        case .filed: return Text("Filed")
        case .nothingToReport: return Text("Nothing to report")
        }
    }

    static func statusTint(_ status: VatReturnStatus) -> Color {
        switch status {
        case .notDue, .nothingToReport: return .secondary
        case .dueIn(let days): return days <= 14 ? Theme.amber : .secondary
        case .overdue: return Theme.bad
        case .uncertain: return Theme.amber
        case .filedElsewhere: return Theme.moneyIn
        case .filed: return Theme.moneyIn
        }
    }

    /// The title of a return by its type (e.g. one missing from the Sondervorauszahlung's basis).
    static func titleString(_ type: VatReturnItem.ReturnType) -> String {
        switch type {
        case .ustva(let period): return periodTitleString(period)
        case .sondervorauszahlung(let year): return String(localized: "Sondervorauszahlung \(String(year))")
        case .dauerfristverlaengerung(let year):
            return String(localized: "Dauerfristverlängerung application \(String(year))")
        case .zm(let period): return String(localized: "ZM \(periodTitleString(period))")
        }
    }

    static func filingState(_ state: VatFiling.State?) -> Text {
        switch state {
        case .accepted: return Text("Accepted")
        case .rejected: return Text("Rejected")
        case .uncertain: return Text("Outcome unknown")
        case .filedElsewhere: return Text("Filed elsewhere")
        case nil: return Text(verbatim: "–")
        }
    }

    static func filingStateTint(_ state: VatFiling.State?) -> Color {
        switch state {
        case .accepted, .filedElsewhere: return Theme.moneyIn
        case .rejected: return Theme.bad
        case .uncertain: return Theme.amber
        case nil: return .secondary
        }
    }

    static func sendBlocker(_ blocker: VatReturnsModel.SendBlocker) -> Text? {
        switch blocker {
        case .cannotBuild, .sending: return nil
        case .unconfirmedTreatments: return Text("Confirm the VAT treatment of every record in this period first.")
        case .noCertificate: return Text("Import your ELSTER certificate in the ELSTER settings.")
        case .notValidated: return Text("Validate the return before sending it.")
        case .validationFailed: return Text("Fix the errors ERiC found, then validate again.")
        case .correctionRequired:
            return Text("This return was already filed. To send it again, turn on Corrected return (Kz10).")
        case .alreadyFiled: return Text("This return was already filed and can't be sent again.")
        case .nothingToReport: return Text("No EU sales to businesses in this period: there is nothing to report.")
        case .missingCustomerVatID: return Text("Enter the customer's VAT ID on every EU sale to a business.")
        case .nothingToCorrect: return Text("This ZM was filed and nothing changed since: there is nothing to correct.")
        case .correctionBasisUnknown:
            return Text("This ZM was marked as filed elsewhere, so the app doesn't know which lines were filed. File the correction in the BZSt online portal.")
        }
    }

    static func progressStep(_ step: EricProgress.Step?) -> Text {
        switch step {
        case .reading: return Text("Reading the return…")
        case .preparing: return Text("Preparing…")
        case .validating: return Text("Validating…")
        case .sending: return Text("Sending to ELSTER…")
        case .printing: return Text("Printing the protocol…")
        case nil: return Text("Working…")
        }
    }

    /// One warning about a record.
    static func issue(_ code: UStVAIssue.Code) -> Text {
        switch code {
        case .draftInPeriod: return Text("Draft in this period – it counts only once approved")
        case .unconfirmedTreatment: return Text("VAT treatment not confirmed – the suggestion is used")
        case .unpaidUnderIst: return Text("Not paid yet – left out under cash accounting (Ist)")
        case .missingEURAmount: return Text("Foreign currency without a conversion rate – left out")
        case .missingVatRows: return Text("No VAT rate on a domestic record – nothing reported")
        case .missingVatRate: return Text("No VAT rate known for the record date – no VAT computed")
        case .missingCustomerVatID: return Text("EU business customer without a VAT ID")
        case .implausibleCustomerVatID: return Text("EU business customer VAT ID doesn't look valid")
        }
    }

    static func issueIcon(_ code: UStVAIssue.Code) -> String {
        switch code {
        case .unconfirmedTreatment: "questionmark.circle"
        case .draftInPeriod: "doc.badge.ellipsis"
        default: "exclamationmark.triangle"
        }
    }

    /// Order of the warning groups on screen.
    static let issueOrder: [UStVAIssue.Code] = [
        .unconfirmedTreatment, .draftInPeriod, .missingEURAmount, .missingVatRows, .missingVatRate,
        .missingCustomerVatID, .implausibleCustomerVatID, .unpaidUnderIst,
    ]

    static func blocker(_ blocker: VatReturnsModel.Blocker) -> Text {
        switch blocker {
        case .herstellerID: return Text("The app has no ELSTER Hersteller-ID.")
        case .identity(.name): return Text("Enter your name in the ELSTER settings.")
        case .identity(.steuernummer): return Text("Enter and check your Steuernummer in the ELSTER settings.")
        case .identity(.finanzamt): return Text("Choose your Finanzamt in the ELSTER settings.")
        case .identity(.vatID): return Text("Enter your USt-IdNr (DE and nine digits) in the ELSTER settings.")
        case .identity(.address): return Text("Enter your street, postal code and city in the ELSTER settings.")
        case .sondervorauszahlung: return Text("Enter the Sondervorauszahlung in the ELSTER settings.")
        }
    }

    /// A short English name of a Kennzahl, or nil for one the app never fills.
    static func kennzahl(_ kz: Kennzahl) -> Text? {
        switch kz {
        case .kz21: Text("EU services to businesses (customer liable)")
        case .kz35: Text("Sales at other rates (net)")
        case .kz36: Text("VAT on sales at other rates")
        case .kz38: Text("Sondervorauszahlung")
        case .kz39: Text("Sondervorauszahlung credited")
        case .kz41: Text("EU deliveries of goods to businesses")
        case .kz43: Text("Exports and other tax-free sales")
        case .kz45: Text("Sales not taxable in Germany")
        case .kz46: Text("Reverse charge, EU services (net)")
        case .kz47: Text("VAT on reverse charge, EU services")
        case .kz61: Text("Input VAT on EU acquisitions")
        case .kz62: Text("Import VAT")
        case .kz66: Text("Input VAT from invoices")
        case .kz67: Text("Input VAT from reverse charge")
        case .kz81: Text("Sales at the standard rate (net)")
        case .kz83: Text("VAT payable (negative: refund)")
        case .kz84: Text("Reverse charge, other services (net)")
        case .kz85: Text("VAT on reverse charge, other services")
        case .kz86: Text("Sales at the reduced rate (net)")
        case .kz89: Text("EU acquisitions at the standard rate (net)")
        case .kz93: Text("EU acquisitions at the reduced rate (net)")
        case .kz95: Text("EU acquisitions at other rates (net)")
        case .kz98: Text("VAT on EU acquisitions at other rates")
        default: nil
        }
    }

    static func flag(_ number: Int) -> Text {
        switch number {
        case 10: Text("Corrected return (Kz10)")
        case 22: Text("Documents submitted separately (Kz22)")
        case 26: Text("Don't use the direct debit mandate (Kz26)")
        case 29: Text("Offset a refund or refund assigned (Kz29)")
        default: Text(verbatim: "Kz\(number)")
        }
    }

    /// The ZM Umsatzart.
    static func umsatzart(_ art: ZMUmsatzart) -> Text {
        switch art {
        case .goods: Text("Goods (L)")
        case .service: Text("Services (S)")
        }
    }

    static func treatment(_ treatment: VatTreatment) -> Text { Text(LocalizedStringKey(treatment.rawValue)) }
}
#endif
