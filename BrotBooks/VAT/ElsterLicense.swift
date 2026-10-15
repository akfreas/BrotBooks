#if os(macOS)
import Observation
import SwiftUI

/// Whether the user acknowledged the data-protection notices the ERiC license requires before ERiC is used
/// (`lizenz.pdf` § 5 Abs. 1 and 2, § 15). Stored per device in `UserDefaults`: it is the device that runs ERiC.
@MainActor
@Observable
final class ElsterLicenseAcknowledgment {
    static let shared = ElsterLicenseAcknowledgment()

    /// `UserDefaults` keys. `acceptedAt` is an ISO 8601 timestamp, so a launch argument can set it
    /// (`-elsterLicense.acceptedAt 2026-10-15T10:00:00Z`).
    static let acceptedAtKey = "elsterLicense.acceptedAt"
    static let ericVersionKey = "elsterLicense.ericVersion"

    private let defaults: UserDefaults
    /// When the notices were acknowledged; nil until then.
    private(set) var acceptedAt: Date?
    /// The ERiC version in the app when they were acknowledged.
    private(set) var ericVersion: String?

    var isAccepted: Bool { acceptedAt != nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        acceptedAt = defaults.string(forKey: Self.acceptedAtKey).flatMap { try? Date($0, strategy: .iso8601) }
        ericVersion = defaults.string(forKey: Self.ericVersionKey)
    }

    func accept(ericVersion: String?, at date: Date = Date()) {
        defaults.set(date.formatted(.iso8601), forKey: Self.acceptedAtKey)
        if let ericVersion { defaults.set(ericVersion, forKey: Self.ericVersionKey) }
        acceptedAt = date
        self.ericVersion = ericVersion
    }
}

extension View {
    /// Shows the content only once the ERiC data-protection notices were acknowledged. Until then it shows a
    /// placeholder and presents `ElsterLicenseSheet`. Apply it to every ELSTER feature's root view.
    func requiresElsterLicenseAcknowledgment() -> some View {
        modifier(ElsterLicenseGate())
    }
}

private struct ElsterLicenseGate: ViewModifier {
    @State private var acknowledgment = ElsterLicenseAcknowledgment.shared
    @State private var showingNotice = false

    func body(content: Content) -> some View {
        Group {
            if acknowledgment.isAccepted {
                content
            } else {
                ContentUnavailableView {
                    Label("Data Protection Notice", systemImage: "hand.raised")
                } description: {
                    Text("Before you use ELSTER features, read and acknowledge the data protection notices of the German tax administration.")
                } actions: {
                    Button("Show Notice") { showingNotice = true }
                        .accessibilityIdentifier("elster.license.show")
                }
                .onAppear { showingNotice = true }
            }
        }
        .sheet(isPresented: $showingNotice) {
            ElsterLicenseSheet { version in
                acknowledgment.accept(ericVersion: version)
                showingNotice = false
            } onCancel: {
                showingNotice = false
            }
        }
    }
}

/// The notices ERiC's license requires (German, verbatim from `lizenz.pdf`), with an explicit acknowledgment.
struct ElsterLicenseSheet: View {
    var onAcknowledge: (_ ericVersion: String?) -> Void
    var onCancel: () -> Void

    private let eric = EricRuntime.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Data Protection Notices")
                        .font(.title2.bold())
                    Text("The ELSTER library (ERiC) used for VAT returns requires BrotBooks to show you these notices from the German tax administration before first use. They are only available in German.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    notice(ElsterLicenseTexts.datenschutzhinweisTitle) {
                        legal(ElsterLicenseTexts.datenschutzhinweis)
                    }
                    notice(ElsterLicenseTexts.protokolldateienTitle) {
                        legal(ElsterLicenseTexts.protokolldateien)
                        LabeledContent {
                            Text(verbatim: logFile.path(percentEncoded: false))
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .accessibilityIdentifier("elster.license.logPath")
                        } label: {
                            Text("Log file on this Mac")
                        }
                        Text("BrotBooks never sends this file anywhere. Share it only if you choose to, for example with support.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    notice(ElsterLicenseTexts.allgemeineInformationenTitle) {
                        ForEach(Array(ElsterLicenseTexts.allgemeineInformationen.enumerated()), id: \.offset) { _, block in
                            blockView(block)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("Not Now", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Acknowledge") { onAcknowledge(eric.version?.displayVersion) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("elster.license.acknowledge")
            }
            .padding(16)
        }
        .frame(width: 640, height: 640)
        .interactiveDismissDisabled()
        .task { await eric.loadVersion() }
    }

    private var logFile: URL { eric.service.logDirectory.appending(path: "eric.log") }

    private func notice<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title).font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 10))
    }

    private func legal(_ text: String) -> some View {
        Text(verbatim: text)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func blockView(_ block: ElsterLicenseTexts.Block) -> some View {
        switch block {
        case .heading(let text):
            Text(verbatim: text).font(.subheadline.bold()).padding(.top, 6)
        case .paragraph(let text):
            legal(text)
        case .item(let text, let level):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: level == 0 ? "•" : "◦")
                legal(text)
            }
            .padding(.leading, CGFloat(level) * 18)
        }
    }
}
#endif
