#if os(macOS)
import BrotBooksKit
import SwiftUI

/// The one-time review before filing: every record in an open period whose VAT treatment is only suggested.
/// Confirm takes the suggestion; the menu picks another treatment. Both store `vat_treatment` explicitly.
struct TreatmentReviewView: View {
    @Environment(AppModel.self) private var app
    let model: VatReturnsModel
    @State private var selection = Set<String>()

    var body: some View {
        let entries = model.review
        Group {
            if entries.isEmpty {
                ContentUnavailableView("All Treatments Confirmed", systemImage: "checkmark.circle",
                                       description: Text("Every record in the open periods has a confirmed VAT treatment."))
            } else {
                List(selection: $selection) {
                    Section {
                        ForEach(entries) { entry in
                            TreatmentReviewRow(entry: entry, record: model.records[entry.recordUID]) { treatment in
                                model.confirm([(entry.recordUID, treatment)], app: app)
                                selection.remove(entry.recordUID)
                            }
                            .tag(entry.recordUID)
                            .accessibilityIdentifier("vat.review.row.\(entry.recordUID)")
                        }
                    } header: {
                        Text("Suggested from each record's region, VAT and customer details. Goods or service can't be told from the record: check those before confirming.")
                            .textCase(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle(Text("Review VAT Treatments"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Select All") { selection = Set(entries.map(\.recordUID)) }
                    .disabled(entries.isEmpty)
                Button {
                    let chosen = entries.filter { selection.contains($0.recordUID) }
                    model.confirm(chosen.map { ($0.recordUID, $0.suggestion.treatment) }, app: app)
                    selection = []
                } label: {
                    Label("Confirm Selected (\(selection.count))", systemImage: "checkmark.circle")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("vat.review.confirmSelected")
            }
        }
        .onChange(of: entries.map(\.recordUID)) { _, uids in selection.formIntersection(uids) }
    }
}

private struct TreatmentReviewRow: View {
    @Environment(AppModel.self) private var app
    let entry: VatTreatmentReview.Entry
    let record: RecordSnapshot?
    let choose: (VatTreatment) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: entry.kind == .income ? "arrow.down.left" : "arrow.up.right")
                        .foregroundStyle(.secondary)
                    Text(verbatim: record?.description ?? String(localized: "Untitled")).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(verbatim: Dates.long(record?.date ?? ""))
                    Text(verbatim: "·")
                    Text(verbatim: Money.format(record?.convertedGrossAmount))
                    Text(verbatim: "·")
                    Text("Return \(VatReturnTexts.periodTitleString(entry.period))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Text("Suggested: \(VatReturnTexts.treatment(entry.suggestion.treatment))")
                    .font(.callout)
                if let alternative = entry.suggestion.alternative {
                    Text("Or: \(VatReturnTexts.treatment(alternative))")
                        .font(.caption)
                        .foregroundStyle(Theme.amber)
                }
            }
            Button("Confirm") { choose(entry.suggestion.treatment) }
                .accessibilityIdentifier("vat.review.confirm.\(entry.recordUID)")
            Menu {
                ForEach(VatTreatment.cases(for: entry.kind), id: \.self) { treatment in
                    Button { choose(treatment) } label: { VatReturnTexts.treatment(treatment) }
                }
                if let record {
                    Divider()
                    Button("Open Record…") { app.open(record) }
                }
            } label: {
                Text("Other…")
            }
            .fixedSize()
        }
        .padding(.vertical, 3)
    }
}
#endif
