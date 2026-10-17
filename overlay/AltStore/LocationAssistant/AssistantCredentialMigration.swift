import Foundation

enum AssistantCredentialMigration {
    static let marker = "assistant.localKeychainMigration.v1"
    static func copyMissing(keys: [String], read: (String, Bool) throws -> Data?, write: (Data, String) throws -> Void) throws {
        guard try read(marker, false) == nil else { return }
        for key in keys {
            if try read(key, false) == nil, let previous = try read(key, true) { try write(previous, key) }
        }
        try write(Data([1]), marker)
    }
}
