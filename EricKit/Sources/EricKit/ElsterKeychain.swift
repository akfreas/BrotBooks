import Foundation
import os
import Security

/// The ELSTER certificate (PKCS#12 bytes) and its PIN in this Mac's Keychain: two generic password items of
/// `service`, never synced (`kSecAttrSynchronizable = false`) and readable only while the Mac is unlocked
/// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
///
/// The items go to the data protection keychain when the app is signed with an application identifier;
/// ad-hoc signed builds (and `swift test`) lack that entitlement (`errSecMissingEntitlement`), so they use the
/// login keychain with the same attributes. The PIN is never logged.
public struct ElsterKeychain: Sendable {
    public struct Error: Swift.Error, Equatable, CustomStringConvertible {
        public var status: OSStatus

        public var description: String {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? ""
            return "Keychain error \(status) \(message)"
        }
    }

    /// The app's items; `-uiTesting` builds use their own service so they never touch the real certificate.
    public static let defaultService = "me.freas.BrotBooks.elster"

    public let service: String

    public init(service: String = ElsterKeychain.defaultService) {
        self.service = service
    }

    private enum Account: String {
        case certificate, pin
    }

    private static let log = Logger(subsystem: "me.freas.BrotBooks", category: "ELSTER")

    /// Whether the data protection keychain is available to this process, probed once by adding and removing an
    /// item (a lookup alone reports "not found" even without the entitlement).
    public static let usesDataProtectionKeychain: Bool = {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "me.freas.BrotBooks.keychain-probe",
            kSecAttrAccount as String: "probe",
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var add = query
        add[kSecValueData as String] = Data()
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess { SecItemDelete(query as CFDictionary) }
        let available = status == errSecSuccess || status == errSecDuplicateItem
        log.info("Keychain: \(available ? "data protection keychain" : "login keychain", privacy: .public) (probe \(status))")
        return available
    }()

    // MARK: Certificate

    /// The stored PKCS#12 certificate, or nil.
    public func certificate() throws(Error) -> Data? { try read(.certificate) }

    public func setCertificate(_ data: Data) throws(Error) { try write(data, .certificate) }

    // MARK: PIN

    /// The stored PIN, or nil.
    public func pin() throws(Error) -> String? {
        try read(.pin).map { String(decoding: $0, as: UTF8.self) }
    }

    public func setPIN(_ pin: String) throws(Error) { try write(Data(pin.utf8), .pin) }

    /// Removes the PIN (after ERiC reported it wrong), keeping the certificate.
    public func removePIN() throws(Error) { try delete(.pin) }

    /// Removes the certificate and the PIN.
    public func removeAll() throws(Error) {
        try delete(.pin)
        try delete(.certificate)
    }

    // MARK: Items

    private func baseQuery(_ account: Account) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecAttrSynchronizable as String: false,
        ]
        if Self.usesDataProtectionKeychain { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }

    private func read(_ account: Account) throws(Error) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Error(status: status) }
        return item as? Data
    }

    private func write(_ data: Data, _ account: Account) throws(Error) {
        let query = baseQuery(account)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Error(status: update) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrLabel as String] = account == .pin ? "BrotBooks ELSTER certificate PIN" : "BrotBooks ELSTER certificate"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error(status: status) }
    }

    private func delete(_ account: Account) throws(Error) {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Error(status: status) }
    }
}
