#if os(macOS)
import BrotBooksKit
import EricKit
import SwiftUI

/// Sending one return: the confirmation (Finanzamt, Steuernummer, period, amount, TEST or PRODUCTION; production
/// needs a second explicit confirmation), ERiC's progress, and the result with the ticket and the protocol.
struct VatSendSheet: View {
    let model: VatReturnsModel
    let item: VatReturnItem
    let session: VatReturnsModel.SendSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch session.stage {
            case .confirm: VatSendConfirmation(model: model, item: item, session: session)
            case .sending: progress
            case .result: VatSendResultView(model: model, item: item, session: session)
            }
        }
        .frame(width: 520)
        .interactiveDismissDisabled(session.stage == .sending)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Sending \(VatReturnTexts.titleString(item))").font(.title3.bold())
                Spacer()
                ModeBadge(isTest: session.isTest)
            }
            ProgressView(value: session.progress?.fraction ?? 0) {
                VatReturnTexts.progressStep(session.progress?.step)
            }
            .accessibilityIdentifier("vat.send.progress")
            Text("Keep the app open until ELSTER answers.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

/// TEST or PRODUCTION.
struct ModeBadge: View {
    let isTest: Bool

    var body: some View {
        Text(isTest ? "TEST" : "PRODUCTION")
            .font(.caption.weight(.heavy))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(.white)
            .background(isTest ? Theme.accent : Theme.bad, in: .rect(cornerRadius: 5))
            .accessibilityIdentifier("vat.send.mode")
    }
}

// MARK: - Confirmation

private struct VatSendConfirmation: View {
    let model: VatReturnsModel
    let item: VatReturnItem
    let session: VatReturnsModel.SendSession
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var confirmedProduction = false
    @State private var confirmedResend = false
    @State private var finanzamtName: String?

    private var credentials: ElsterCredentials { ElsterCredentials.shared }
    private var identity: TaxIdentity { item.configuration.identity }
    private var needsPIN: Bool { !credentials.usesStubTransport && !credentials.hasPIN }
    private var needsResendConfirmation: Bool {
        model.filingSummary(item).needsResendConfirmation(isTest: session.isTest)
    }

    private var canSend: Bool {
        (session.isTest || confirmedProduction) && (!needsResendConfirmation || confirmedResend)
            && (!needsPIN || !pin.isEmpty)
    }

    var body: some View {
        let flags = model.flags[item.id] ?? []
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Send to ELSTER").font(.title2.bold())
                Spacer()
                ModeBadge(isTest: session.isTest)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Return") { VatReturnTexts.title(item) }
                if let period = item.period {
                    row("Period") { Text(verbatim: "\(period.year) / Zeitraum \(period.zeitraum)") }
                }
                row("Finanzamt") {
                    Text(verbatim: finanzamtName.map { "\($0) (\(identity.finanzamt))" } ?? identity.finanzamt)
                }
                row("Steuernummer") {
                    Text(verbatim: identity.steuernummerRegional.isEmpty
                         ? identity.steuernummer : "\(identity.steuernummerRegional) (\(identity.steuernummer))")
                        .monospacedDigit()
                }
                if let main = model.mainAmount(item) {
                    row(LocalizedStringKey(main.kennzahl.elementName)) {
                        Text(verbatim: Money.format(main.amount)).monospacedDigit().fontWeight(.semibold)
                    }
                }
                if flags.contains(.correction) {
                    row("Corrected return") { Text("Yes (Kz10)") }
                }
                row("Certificate") {
                    if credentials.usesStubTransport {
                        Text("Stub transport: nothing is sent").foregroundStyle(Theme.amber)
                    } else {
                        Text(verbatim: credentials.info?.holder ?? "–")
                    }
                }
            }
            .accessibilityIdentifier("vat.send.summary")

            if session.isTest {
                Label("Test mode: the return carries the ELSTER test marker, so the Finanzamt does not process it.",
                      systemImage: "testtube.2")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if needsResendConfirmation {
                VStack(alignment: .leading, spacing: 6) {
                    Label("The last send of this return ended without an answer from ELSTER. It may have arrived: a second return for the same period is a duplicate filing.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.amber)
                    Toggle("I checked Mein ELSTER: this return did not arrive. Send it again.", isOn: $confirmedResend)
                        .accessibilityIdentifier("vat.send.confirmResend")
                }
                .font(.callout)
            }

            if needsPIN {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField("Certificate PIN", text: $pin)
                        .textContentType(.password)
                        .accessibilityIdentifier("vat.send.pin")
                    Text("The PIN is checked against your certificate and kept in this Mac's Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let error = session.pinError {
                Label { Text(verbatim: error) } icon: { Image(systemName: "xmark.octagon.fill") }
                    .foregroundStyle(Theme.bad)
                    .accessibilityIdentifier("vat.send.pinError")
            }

            if !session.isTest {
                Toggle(isOn: $confirmedProduction) {
                    Text("I want to file this return with the Finanzamt.").fontWeight(.semibold)
                }
                .accessibilityIdentifier("vat.send.confirmProduction")
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    model.sendSession = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    Task { await model.send(item, pin: needsPIN ? pin : nil) }
                } label: {
                    Label(session.isTest ? "Send Test" : "File with the Finanzamt", systemImage: "paperplane.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSend)
                .accessibilityIdentifier("vat.send.confirm")
            }
        }
        .padding(24)
        .task { await loadFinanzamtName() }
    }

    private func row<Content: View>(_ label: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            content().textSelection(.enabled)
        }
    }

    private func loadFinanzamtName() async {
        let bufa = identity.finanzamt
        guard bufa.count == 4 else { return }
        let list = try? await EricRuntime.shared.service.finanzaemter(landNummer: String(bufa.prefix(2)))
        finanzamtName = list?.first { $0.bufaNummer == bufa }?.name
    }
}

// MARK: - Result

private struct VatSendResultView: View {
    let model: VatReturnsModel
    let item: VatReturnItem
    let session: VatReturnsModel.SendSession
    @Environment(\.dismiss) private var dismiss

    private var filing: VatFiling? {
        session.filingUID.flatMap { uid in model.filings[item.id]?.first { $0.uid == uid } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(VatReturnTexts.titleString(item)).font(.title3.bold())
                Spacer()
                ModeBadge(isTest: session.isTest)
            }
            outcome
            if let saveError = session.saveError {
                Label { Text("The filing couldn't be saved completely: \(saveError)") } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(Theme.amber)
            }
            HStack {
                if let filing, filing.protocolPath != nil {
                    Button {
                        Task {
                            await model.showProtocol(filing, item: item)
                            model.sendSession = nil
                        }
                    } label: {
                        Label("Show Protocol", systemImage: "doc.richtext")
                    }
                    .accessibilityIdentifier("vat.send.showProtocol")
                }
                Spacer()
                Button("Close") {
                    model.sendSession = nil
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("vat.send.close")
            }
        }
        .padding(24)
        .accessibilityIdentifier("vat.send.result")
    }

    @ViewBuilder private var outcome: some View {
        switch session.outcome {
        case .accepted(let ticket, let text):
            headline(session.isTest ? "Accepted by ELSTER (test)" : "Accepted by ELSTER", icon: "checkmark.seal.fill",
                     tint: Theme.moneyIn)
            if session.isTest {
                Text("A test filing never counts as filed: the return is still due for real.")
                    .foregroundStyle(.secondary)
            }
            details(ticket: ticket, code: nil, text: text)
        case .rejected(let code, let text, let ticket):
            headline("Rejected by ELSTER", icon: "xmark.octagon.fill", tint: Theme.bad)
            Text(verbatim: text)
                .font(.body.weight(.medium))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bad.opacity(0.1), in: .rect(cornerRadius: 8))
                .accessibilityIdentifier("vat.send.serverText")
            details(ticket: ticket, code: code, text: nil)
        case .uncertain(let ticket, let code, let text):
            headline("ELSTER didn't confirm the return", icon: "questionmark.diamond.fill", tint: Theme.amber)
            Text("The return may have arrived. Check Mein ELSTER before sending it again: a second return for the same period is a duplicate filing.")
                .fixedSize(horizontal: false, vertical: true)
            details(ticket: ticket, code: String(code), text: text)
        case .pinWrong:
            headline("The PIN is wrong", icon: "key.slash", tint: Theme.bad)
            Text("Nothing was sent. The stored PIN was removed; enter the PIN again when you send.")
        case .pinLocked:
            headline("The certificate's PIN is locked", icon: "lock.fill", tint: Theme.bad)
            Text("Nothing was sent. Unlock or renew the certificate in Mein ELSTER, then import it again.")
        case .validationFailed(let validation):
            headline("ERiC found errors", icon: "xmark.octagon.fill", tint: Theme.bad)
            Text("Nothing was sent.")
            ForEach(Array(validation.errors.enumerated()), id: \.offset) { _, message in
                Text(verbatim: message.text).font(.callout).textSelection(.enabled)
            }
        case .failed(let code, let text):
            headline("The return couldn't be sent", icon: "xmark.octagon.fill", tint: Theme.bad)
            Text("Nothing was sent.")
            details(ticket: nil, code: String(code), text: text)
        case nil:
            EmptyView()
        }
    }

    private func headline(_ title: LocalizedStringKey, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tint)
            .accessibilityIdentifier("vat.send.outcome")
    }

    private func details(ticket: String?, code: String?, text: String?) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            if let ticket {
                GridRow {
                    Text("Ticket").foregroundStyle(.secondary)
                    Text(verbatim: ticket).monospaced().textSelection(.enabled)
                        .accessibilityIdentifier("vat.send.ticket")
                }
            }
            if let code {
                GridRow {
                    Text("Code").foregroundStyle(.secondary)
                    Text(verbatim: code).monospacedDigit().textSelection(.enabled)
                }
            }
            if let text, !text.isEmpty {
                GridRow {
                    Text("Message").foregroundStyle(.secondary)
                    Text(verbatim: text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout)
    }
}

// MARK: - Filed elsewhere

/// Records a return as filed outside the app, with its amount (Kz83, or Kz38) and date when known.
struct MarkFiledElsewhereSheet: View {
    let model: VatReturnsModel
    let item: VatReturnItem
    @Environment(\.dismiss) private var dismiss
    @State private var knowsAmount = true
    @State private var amountText = ""
    @State private var filedOn = Date()

    var body: some View {
        let kennzahl = model.mainAmount(item)?.kennzahl ?? (item.period != nil ? .kz83 : .kz38)
        VStack(alignment: .leading, spacing: 14) {
            Text("Mark as Filed Elsewhere").font(.title3.bold())
            Text("For a return filed with Mein ELSTER or by your accountant. It then counts as filed, and its amount counts toward next year's Sondervorauszahlung.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(VatReturnTexts.titleString(item)).font(.headline)
            if item.filingKind != .dauerfristverlaengerung {
                Toggle("I know the amount filed", isOn: $knowsAmount)
                if knowsAmount {
                    LabeledContent(kennzahl.elementName) {
                        TextField("Amount", text: $amountText, prompt: Text(verbatim: "0.00"))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 160)
                            .foregroundStyle(amount == nil && !amountText.isEmpty ? Theme.bad : Color.primary)
                            .accessibilityIdentifier("vat.elsewhere.amount")
                    }
                }
            }
            DatePicker("Filed on", selection: $filedOn, displayedComponents: .date)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Mark as Filed") {
                    model.markFiledElsewhere(item, amount: knowsAmount ? amount : nil, filedOn: ISODate.today(filedOn))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(knowsAmount && item.filingKind != .dauerfristverlaengerung && amount == nil)
                .accessibilityIdentifier("vat.elsewhere.save")
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            amountText = model.mainAmount(item).map { Money.plainString($0.amount) } ?? ""
        }
    }

    private var amount: Decimal? { Money.parseInput(amountText) }
}
#endif
