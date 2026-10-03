import Foundation

enum AssistantCertificateError: Error, LocalizedError {
    case missingPrivateKey, certificateNotOnAccount, invalidFile
    var errorDescription: String? {
        switch self {
        case .missingPrivateKey:
            return "此账号已有签名证书，但定位助手没有对应私钥。请关闭登录页，在设置中导入原签名工具导出的完整 .p12/.pfx 证书或 SideStore 账号备份，再登录。本 App 不会撤销已有证书。"
        case .certificateNotOnAccount:
            return "导入的证书不属于当前账号的有效证书，可能账号不同或证书已被撤销。请核对签名账号及证书；不会自动替换或撤销证书。"
        case .invalidFile:
            return "证书无法读取、密码错误或文件没有私钥。请选择完整 .p12/.pfx，或 SideStore 加密的 .sideconf 账号备份；配对文件和公开 .cer 证书不能用于续签。"
        }
    }
}

enum AssistantSigningPolicy {
    static func matches(_ serial: String, portalSerials: [String], hasPrivateKey: Bool) -> Bool {
        hasPrivateKey && !serial.isEmpty && portalSerials.contains { $0.caseInsensitiveCompare(serial) == .orderedSame }
    }
    static func canCreateCertificate(portalSerials: [String], hasImportedCertificate: Bool) -> Bool {
        portalSerials.isEmpty && !hasImportedCertificate
    }
}
