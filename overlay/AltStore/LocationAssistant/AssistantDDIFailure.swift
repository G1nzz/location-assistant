import Foundation

enum AssistantDDIStage: String, Sendable {
    case configuration = "读取映像配置"
    case cacheDirectory = "创建映像缓存"
    case bundledRead = "读取安装包内开发者映像"
    case download = "下载开发者映像"
    case verification = "校验开发者映像"
    case cacheCommit = "保存已验证映像"
    case preparation = "准备开发者服务"
}

// Keep only allowlisted stages/resources/domains and numeric codes. Never save
// localizedDescription, userInfo, URLs, filesystem paths or nested raw errors.
struct AssistantDDIFailure: LocalizedError, Sendable {
    let stage: AssistantDDIStage
    let asset: String?
    let domain: String
    let code: Int
    let advice: String

    init(stage: AssistantDDIStage, asset: String? = nil, error: Error) {
        self.stage = stage
        let names = ["Image.dmg", "BuildManifest.plist", "Image.dmg.trustcache", "Image.dmg.cryptex_info", "Image.dmg.root_hash"]
        self.asset = asset.flatMap { names.contains($0) ? $0 : nil }
        let ns = error as NSError
        if let ddi = error as? AssistantDDIError {
            domain = "AssistantDDI"
            switch ddi {
            case .manifest: code = 1
            case .response(let status): code = status ?? 2
            case .integrity: code = 3
            case .sizeLimit: code = 4
            case .native(let value): code = Int(value)
            }
            if case .integrity = ddi, stage == .bundledRead {
                advice = "安装包内开发者映像校验失败，已停止使用。请保留 App 数据并重新安装完整的本版安装包。"
            } else { advice = ddi.localizedDescription }
        } else {
            domain = [NSURLErrorDomain, NSCocoaErrorDomain, NSPOSIXErrorDomain].contains(ns.domain) ? ns.domain : "其他错误域"
            code = ns.code
            if ns.domain == NSURLErrorDomain {
                switch ns.code {
                case NSURLErrorBadURL, NSURLErrorUnsupportedURL:
                    advice = "下载请求未能建立。请保留脱敏诊断信息，以便检查映像资源与下载请求。"
                case NSURLErrorTimedOut: advice = "下载连接超时。请先用能访问下载源的网络，在设置中单独下载映像。"
                case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: advice = "下载域名解析失败。请检查当前网络，再尝试提前下载映像。"
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost:
                    advice = "下载网络不可达或连接已中断。请检查网络，再尝试提前下载映像。"
                case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
                    advice = "下载安全连接失败。请检查网络与系统时间；不会跳过证书验证。"
                case NSURLErrorCancelled: advice = "下载已中断。请保持 App 在前台，下载完成后再切换 VPN。"
                default: advice = "下载请求失败。请检查网络，再尝试提前下载映像。"
                }
            } else if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError {
                advice = "设备存储空间不足，无法保存映像。请释放空间后重试。"
            } else if ns.domain == NSCocoaErrorDomain || ns.domain == NSPOSIXErrorDomain {
                advice = "本地文件处理失败。请保留 App 数据并重试；若仍失败，提供脱敏诊断中的阶段和代码。"
            } else {
                advice = "此阶段发生未分类错误，请提供脱敏诊断中的阶段和代码。"
            }
        }
    }

    static func convert(_ error: Error, stage: AssistantDDIStage, asset: String? = nil) -> Error {
        if error is CancellationError || Task.isCancelled { return CancellationError() }
        if let known = error as? Self { return known }
        return Self(stage: stage, asset: asset, error: error)
    }

    var errorDescription: String? { "\(stage.rawValue)失败（\(code)）。\(advice)" }
    var diagnostic: String {
        "阶段：\(stage.rawValue)\n资源：\(asset ?? "未记录")\n错误域：\(domain)\n错误代码：\(code)\n\(advice)"
    }
}
