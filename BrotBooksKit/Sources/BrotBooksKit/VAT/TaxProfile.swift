import Foundation
import SwiftData

/// The synced tax profile: identity, test mode and the effective-dated filing settings (`TaxSettings`).
/// CloudKit rules as in `Models.swift`: every property optional or defaulted, additive changes only. The
/// settings periods are one JSON array (`[TaxSettingsPeriod]`, money as decimal strings). The certificate and
/// PIN are not stored here; they stay in this Mac's Keychain.
@Model
public final class TaxProfile {
    public var uid: String = UUID().uuidString
    public var name: String?
    public var street: String?
    public var houseNumber: String?
    public var postalCode: String?
    public var city: String?
    public var phone: String?
    public var email: String?
    /// 13-digit ELSTER format.
    public var steuernummer: String?
    /// 4-digit Finanzamt number.
    public var finanzamt: String?
    /// USt-IdNr.
    public var vatID: String?
    public var testMode: Bool = true
    /// JSON `[TaxSettingsPeriod]`.
    public var settingsPeriods: Data?
    /// JSON `VorsteuerShareRules`; nil while the defaults apply.
    public var vorsteuerShareRules: Data?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init() {}

    /// The profile as a value. Unreadable settings JSON reads as no periods.
    public var settings: TaxSettings {
        let periods = settingsPeriods.flatMap { try? JSONDecoder().decode([TaxSettingsPeriod].self, from: $0) } ?? []
        let identity = TaxIdentity(
            name: name ?? "", street: street ?? "", houseNumber: houseNumber ?? "", postalCode: postalCode ?? "",
            city: city ?? "", phone: phone ?? "", email: email ?? "", steuernummer: steuernummer ?? "",
            finanzamt: finanzamt ?? "", vatID: vatID ?? "")
        let rules = vorsteuerShareRules.flatMap { try? JSONDecoder().decode(VorsteuerShareRules.self, from: $0) }
        return TaxSettings(identity: identity, testMode: testMode, periods: periods,
                           vorsteuerShareRules: rules ?? .default)
    }

    /// Writes `settings` into the profile (empty identity fields are stored as nil) and bumps `updatedAt`.
    public func apply(_ settings: TaxSettings) {
        let i = settings.identity
        func stored(_ s: String) -> String? { s.isEmpty ? nil : s }
        name = stored(i.name)
        street = stored(i.street)
        houseNumber = stored(i.houseNumber)
        postalCode = stored(i.postalCode)
        city = stored(i.city)
        phone = stored(i.phone)
        email = stored(i.email)
        steuernummer = stored(i.steuernummer)
        finanzamt = stored(i.finanzamt)
        vatID = stored(i.vatID)
        testMode = settings.testMode
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        settingsPeriods = try? encoder.encode(settings.periods)
        vorsteuerShareRules = settings.vorsteuerShareRules == .default ? nil : try? encoder.encode(settings.vorsteuerShareRules)
        updatedAt = Date()
    }

    /// The profile in use when several exist (two devices seeding before CloudKit merges them): the most
    /// recently updated one, then the lowest `uid`, so every device picks the same.
    public static func current(in context: ModelContext) throws -> TaxProfile? {
        try context.fetch(FetchDescriptor<TaxProfile>()).min { a, b in
            a.updatedAt != b.updatedAt ? a.updatedAt > b.updatedAt : a.uid < b.uid
        }
    }

    /// The current profile, creating and saving one with `TaxSettings.initial` when none exists.
    @MainActor
    public static func loadOrCreate(in context: ModelContext) throws -> TaxProfile {
        if let profile = try current(in: context) { return profile }
        let profile = TaxProfile()
        profile.apply(.initial)
        context.insert(profile)
        try context.save()
        return profile
    }

    /// The settings of the current profile (seeding it when none exists).
    @MainActor
    public static func load(in context: ModelContext) throws -> TaxSettings {
        try loadOrCreate(in: context).settings
    }

    /// Saves `settings` into the current profile (creating it when none exists).
    @MainActor
    public static func save(_ settings: TaxSettings, in context: ModelContext) throws {
        let profile = try loadOrCreate(in: context)
        profile.apply(settings)
        try context.save()
    }
}
