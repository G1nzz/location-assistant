import Foundation

enum AssistantPairingError: Error, LocalizedError {
    case invalid, wrongDevice
    var errorDescription: String? {
        switch self {
        case .invalid: return "配对文件格式不完整或无法读取。请选择本设备的配对 plist 文件。"
        case .wrongDevice: return "该配对文件属于另一台设备，已拒绝替换当前文件。请导入本设备的配对文件。"
        }
    }
}

enum AssistantPairingPolicy {
    enum Kind { case remote, lockdown }
    struct Snapshot { let content: String; let kind: Kind }
    static func normalize(_ data: Data, expectedUDID: String? = nil) throws -> Snapshot {
        guard !data.isEmpty, data.count <= 2_000_000,
              let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw AssistantPairingError.invalid
        }
        func text(_ key: String) -> String? {
            guard let value = plist[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        func bytes(_ key: String) -> Bool {
            if let value = plist[key] as? Data { return !value.isEmpty }
            if let value = plist[key] as? [UInt8] { return !value.isEmpty }
            return false
        }
        let kind: Kind
        if text("identifier") != nil && bytes("private_key") && bytes("public_key") {
            kind = .remote
        } else {
            guard ["UDID", "SystemBUID", "HostID", "WiFiMACAddress"].allSatisfy({ text($0) != nil }),
                  ["RootPrivateKey", "HostPrivateKey", "RootCertificate", "HostCertificate", "DeviceCertificate", "EscrowBag"].allSatisfy(bytes) else {
                throw AssistantPairingError.invalid
            }
            if let expected = expectedUDID, expected.count >= 16,
               expected.allSatisfy({ "0123456789abcdefABCDEF-".contains($0) }),
               text("UDID")?.caseInsensitiveCompare(expected) != .orderedSame {
                throw AssistantPairingError.wrongDevice
            }
            kind = .lockdown
        }
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        guard let content = String(data: xml, encoding: .utf8) else { throw AssistantPairingError.invalid }
        return Snapshot(content: content, kind: kind)
    }
}
