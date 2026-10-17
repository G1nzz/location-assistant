import Foundation
import Security

enum AssistantLocalKeychain {
    private static let service = "com.locationassistant.personal"
    private static let marker = AssistantCredentialMigration.marker

    private static func query(_ key: String? = nil, synchronized: Bool = false) -> [String: Any] {
        var result: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrSynchronizable as String: synchronized]
        if let key { result[kSecAttrAccount as String] = key }
        return result
    }

    static func read(_ key: String, synchronized: Bool = false) throws -> Data? {
        var request = query(key, synchronized: synchronized)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else {
            throw AssistantLoginError.storage(OSStatusCode: Int(status))
        }
        return data
    }

    static func write(_ data: Data?, key: String) throws {
        let request = query(key)
        guard let data else {
            let status = SecItemDelete(request as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AssistantLoginError.storage(OSStatusCode: Int(status)) }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: data,
                                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(request.merging(attributes) { _, new in new } as CFDictionary, nil)
            if status == errSecDuplicateItem { status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary) }
        }
        guard status == errSecSuccess else { throw AssistantLoginError.storage(OSStatusCode: Int(status)) }
        guard try read(key) == data else { throw AssistantLoginError.storage(OSStatusCode: Int(errSecDecode)) }
    }

    // Copy once, then leave all synchronized originals untouched so another device is unaffected.
    // A failed copy leaves the marker unset; the next launch can resume without replacing local items.
    static func migrateIfNeeded() throws {
        var keys = ["appleIDEmailAddress", "appleIDPassword", "appleIDAdsid", "appleIDXcodeToken",
                    "signingCertificate", "signingCertificatePassword", "signingCertificatePrivateKey",
                    "signingCertificateSerialNumber", "identifier", "adiPb"]
        keys += (UserDefaults.standard.stringArray(forKey: "importedCertificateSerials") ?? []).map { "importedCert_" + $0 }
        try AssistantCredentialMigration.copyMissing(keys: keys,
            read: { try read($0, synchronized: $1) }, write: { try write($0, key: $1) })
    }

    static func clearLocalItems() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AssistantLoginError.storage(OSStatusCode: Int(status)) }
        // Do not resurrect synchronized legacy credentials after an explicit local reset.
        try write(Data([1]), key: marker)
    }
}
