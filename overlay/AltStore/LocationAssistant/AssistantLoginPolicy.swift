import Foundation

enum AssistantLoginPolicy {
    static let serviceURLs = ["https://mac-ani.jkcoxson.com", "https://ani.jkcoxson.com"]
    static let originalServiceKey = "assistant.useOriginalLoginService"
    static var usesCompatibleService: Bool { !UserDefaults.standard.bool(forKey: originalServiceKey) }

    struct Client: Decodable {
        let clientInfo: String
        let userAgent: String
        enum CodingKeys: String, CodingKey { case clientInfo = "client_info", userAgent = "user_agent" }
    }

    static func decodeClient(_ data: Data) throws -> Client {
        guard data.count <= 32_768 else { throw AssistantLoginError.invalidServiceResponse }
        let client = try JSONDecoder().decode(Client.self, from: data)
        for value in [client.clientInfo, client.userAgent] {
            guard !value.isEmpty, value.utf8.count <= 1024,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw AssistantLoginError.invalidServiceResponse
            }
        }
        return client
    }
}

enum AssistantLoginError: Error, LocalizedError {
    case invalidServiceResponse, serviceUnavailable, storage(OSStatusCode: Int)
    var errorDescription: String? {
        switch self {
        case .invalidServiceResponse: return "登录认证服务返回了无效配置，请稍后重试。"
        case .serviceUnavailable: return "暂时无法连接登录认证服务。请检查互联网连接，或在设置中检查登录服务；无需重新导入签名证书。"
        case .storage(let code): return "无法读取或保存本设备的登录凭据（钥匙串代码 \(code)）。请先解锁设备，再重新打开 App；已有证书不会被撤销。"
        }
    }
}

enum AssistantErrorPresentation {
    // Never include raw userInfo, auth responses, device IDs, tokens or account strings.
    static func describe(domain: String, code: Int, authenticationCode: Int? = nil) -> String {
        let actualCode = authenticationCode ?? code
        switch actualCode {
        case -80045: return "Apple 暂时拒绝此登录请求（-80045）。请在设置中检查登录服务后重试；无需更换设备 Apple ID 或重新导入证书。"
        case -22411: return "Apple 双重验证未完成（-22411）。请完成受信任设备收到的验证码验证；仍失败时保留此代码。"
        case -22406: return "Apple 签名账号或密码未通过验证（-22406）。请核对工具中的签名账号。"
        case -45061: return "登录认证缓存已失效（-45061）。请在设置中重建登录服务缓存，再登录。此操作不会撤销签名证书。"
        case -1009, -1001, -1003, -1004: return "登录网络不可用或请求超时（\(actualCode)）。请检查互联网连接，稍后重试。"
        case -25300, -25293, -34018: return "本设备钥匙串访问失败（\(actualCode)）。请解锁设备后重新打开；暂勿删除 App。"
        default:
            let known = ["NSURLErrorDomain": "网络", "NSOSStatusErrorDomain": "钥匙串", "SideStore.OperationError": "续签流程", "SideSign.DeveloperPortalError": "Apple 登录", "Minimuxer.MinimuxerError": "设备连接"]
            let category = known[domain] ?? "底层服务"
            return "\(category)失败（代码 \(actualCode)）。请记录本提示，以便区分登录、连接和续签故障。"
        }
    }
}
