import Foundation

// Only local, sanitized operation receipts. A stored receipt is not a live Apple
// session, and a process restart is never treated as proof of installation.
struct AssistantSigningHistory: Codable {
    enum Kind: String, Codable {
        case certificateSaved, accountStarted, accountVerified, accountFailed
        case refreshStarted, refreshAccepted, refreshFailed, refreshUnconfirmed
    }
    struct Event: Codable {
        let kind: Kind
        let date: Date
        let message: String?
    }
    struct Receipt: Codable {
        let date: Date
        let profileExpiration: Date
    }
    static let key = "assistant.signingHistory.v1"
    private(set) var event: Event?
    private(set) var receipt: Receipt?

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key), data.count <= 16_384,
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    mutating func record(_ kind: Kind, message: String? = nil, expiration: Date? = nil,
                         now: Date = Date(), defaults: UserDefaults = .standard) {
        let validExpiration = expiration.map { $0 > now } ?? false
        let resolved: Kind = kind == .refreshAccepted && !validExpiration ? .refreshUnconfirmed : kind
        event = Event(kind: resolved, date: now, message: message.map { String($0.prefix(768)) })
        if resolved == .refreshAccepted, let expiration {
            receipt = Receipt(date: now, profileExpiration: expiration)
        }
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    var summary: String {
        guard let event else { return "尚无签名验证记录；定位功能可单独使用" }
        switch event.kind {
        case .certificateSaved: return "上次已保存续签证书；尚未完成本次续签"
        case .accountStarted: return "上次账号验证未收到完成结果；可重新验证"
        case .accountVerified: return "上次账号验证已完成；不代表当前 Apple 会话有效或已续签"
        case .accountFailed: return "上次账号验证失败：\(event.message ?? "请查看脱敏诊断")"
        case .refreshStarted: return "上次已发起续签，未收到完成回执；可能被中断或由系统接管安装，请核对结果"
        case .refreshAccepted: return "上次续签流程已返回成功；回执保存在本设备"
        case .refreshUnconfirmed: return "续签流程已返回，但未读取到有效的描述文件到期时间；本次结果尚未确认"
        case .refreshFailed: return "上次续签失败：\(event.message ?? "请查看脱敏诊断")"
        }
    }
}
