import SwiftUI
import BrotBooksKit

struct TaxCard: View {
    let taxes: TaxEstimate
    let partial: Bool
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(Text("Taxes to be paid · \(String(taxes.year))"))
                Spacer()
                Pill(text: Text("Estimate"))
            }
            VStack(alignment: .leading, spacing: 4) {
                AmountText(value: taxes.totalDue)
                    .accessibilityIdentifier("dashboard.taxTotal")
                Text(partial ? "On income and expenses so far this year, after VAT already paid"
                             : "For the full year, after VAT already paid")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) { breakdown }
                VStack(alignment: .leading, spacing: 10) { breakdown }
            }
            DisclosureGroup(isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("VAT owed", value: Money.format(taxes.vat.liability))
                    LabeledContent("VAT already paid", value: Money.format(taxes.vat.payments))
                    ForEach(taxes.assumptions, id: \.self) { line in
                        Label { Text(LocalizedStringKey(line)) } icon: { Image(systemName: "info.circle") }
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            } label: {
                Text("Taxable profit \(Money.format(taxes.incomeTax.taxableProfit)) · §32a EStG \(String(taxes.incomeTax.tariffYear)) tariff")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.taxCard")
    }

    @ViewBuilder private var breakdown: some View {
        let vat = taxes.vat.outstanding
        BreakdownItem(label: vat < 0 ? Text("VAT credit") : Text("VAT outstanding"), value: vat)
        BreakdownItem(label: Text("Income tax"), value: taxes.incomeTax.incomeTax)
        BreakdownItem(label: Text("Solidarity surcharge"), value: taxes.incomeTax.solidaritySurcharge)
    }
}

private struct BreakdownItem: View {
    let label: Text
    let value: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            label.font(.caption).foregroundStyle(.secondary)
            Text(verbatim: Money.format(value)).font(.body.weight(.medium)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct StatCard: View {
    let label: Text
    let net: Decimal
    let gross: Decimal
    let previousNet: Decimal
    let previousLabel: Text
    /// Rising expenses are bad news: color the change red instead of green.
    var upIsBad = false
    /// Accessibility identifier of the card ("dashboard.incomeCard"); the net amount gets ".net" appended.
    var identifier = ""
    /// Drafts waiting for review, shown as a link that calls `showDrafts` (expenses only).
    var drafts = 0
    var showDrafts: (() -> Void)?

    var body: some View {
        let change = DashboardMath.percentChange(current: net, previous: previousNet)
        let up = (change ?? 0) >= 0
        let good = up != upIsBad
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(label)
            VStack(alignment: .leading, spacing: 2) {
                AmountText(value: net, size: 28)
                    .accessibilityIdentifier("\(identifier).net")
                Text("Net, excl. VAT · \(Money.format(gross)) gross")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let change {
                    Label {
                        Text(verbatim: Self.percent(change))
                    } icon: {
                        Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(good ? Theme.moneyIn : Theme.bad)
                    .accessibilityLabel(Text(up ? "Up \(Self.percent(change))" : "Down \(Self.percent(change))"))
                }
                Group {
                    if previousNet == 0 && change == nil {
                        Text("Nothing to compare \(previousLabel)")
                    } else {
                        Text("\(Money.format(previousNet)) \(previousLabel)")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(identifier).previous")
            }
            if drafts > 0, let showDrafts {
                Button(action: showDrafts) {
                    Label("^[\(drafts) draft](inflect: true) to review", systemImage: "tray.full")
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .help(Text("Drafts are not counted in totals until you approve them"))
                .accessibilityIdentifier("\(identifier).drafts")
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    static func percent(_ value: Decimal) -> String {
        let magnitude = value < 0 ? -value : value
        return Money.plainString(Money.rounded(magnitude, scale: 1)) .appendingDecimalZero + "%"
    }
}

private extension String {
    /// "12" → "12.0" so percentages always show one decimal.
    var appendingDecimalZero: String { contains(".") ? self : self + ".0" }
}
