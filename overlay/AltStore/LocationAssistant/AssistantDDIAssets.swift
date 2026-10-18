// DDI selection follows pinned StikDebug 3.1.13. See THIRD_PARTY_NOTICES.md.
import Foundation
import CryptoKit

enum AssistantDDIMethod: String, Codable, Sendable {
    case personalized, cryptex
    static func select(_ version: OperatingSystemVersion) -> Self {
        version.majorVersion > 26 || (version.majorVersion == 26 && version.minorVersion >= 4)
            ? .cryptex : .personalized
    }
    static var current: Self { select(ProcessInfo.processInfo.operatingSystemVersion) }
}

struct AssistantDDIManifest: Codable, Sendable {
    struct Asset: Codable, Sendable {
        let method: AssistantDDIMethod
        let name: String
        let url: String
        let size: Int
        let sha256: String
    }
    let repository: String
    let commit: String
    let files: [Asset]

    func assets(for method: AssistantDDIMethod) throws -> [Asset] {
        let selected = files.filter { $0.method == method }
        let names = method == .cryptex
            ? ["BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache", "Image.dmg.cryptex_info", "Image.dmg.root_hash"]
            : ["BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"]
        guard commit.count == 40, selected.count == names.count, Set(selected.map(\.name)) == Set(names) else {
            throw AssistantDDIError.manifest
        }
        for item in selected {
            guard item.size > 0, item.size <= 100_000_000, item.sha256.count == 64,
                  let url = URL(string: item.url), url.scheme == "https", url.host == "raw.githubusercontent.com",
                  url.path.hasPrefix("/doronz88/DeveloperDiskImage/\(commit)/"),
                  url.lastPathComponent == item.name else { throw AssistantDDIError.manifest }
        }
        return selected
    }
}

enum AssistantDDIError: LocalizedError {
    case manifest, response, integrity, native(Int32)
    var errorDescription: String? {
        switch self {
        case .manifest: return "本版开发者映像配置无效，请保留 App 数据并更新安装包。"
        case .response: return "开发者映像下载失败，请检查网络后重试；不需要重新登录签名账号。"
        case .integrity: return "开发者映像大小或校验值不符，已拒绝使用；请重试下载。"
        case .native(let code): return AssistantDDIStatus.message(code)
        }
    }
}

enum AssistantDDIStatus {
    static func message(_ code: Int32) -> String {
        switch code {
        case 20: return "开发者映像尚未挂载，请在设置中准备定位开发服务，或点击开始模拟自动准备。"
        case 21: return "无法读取开发者映像状态，请检查 LocalDevVPN、本设备远程配对和开发者模式；尚未确认映像缺失。"
        case 22: return "开发者模式未开启，请在系统设置中开启后按系统提示重启。"
        case 23: return "开发者映像挂载失败，请检查网络、LocalDevVPN 与系统支持；未提交新位置。"
        case 24: return "挂载后仍无法确认开发者映像就绪，已停止后续定位操作，请检查开发服务后重试。"
        case 25: return "开发者映像文件无法读取，请重新准备定位开发服务。"
        default: return "开发者服务准备失败（\(code)），请检查连接与配对。"
        }
    }
}

// URLSession writes to disk; cap the transfer as it arrives. Reject redirects
// outside the pinned HTTPS host. No account, pairing or certificate is supplied.
private final class AssistantDDIDownloadLimit: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let limit: Int64
    init(limit: Int) { self.limit = Int64(limit) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct AssistantDDIAssets {
    typealias Download = (URL, Int) async throws -> (URL, URLResponse)
    let manifest: AssistantDDIManifest
    let root: URL
    let download: Download

    static func installed() throws -> Self {
        guard let file = Bundle.main.url(forResource: "AssistantDDIManifest", withExtension: "json") else {
            throw AssistantDDIError.manifest
        }
        let manifest = try JSONDecoder().decode(AssistantDDIManifest.self, from: Data(contentsOf: file))
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AssistantDDI", isDirectory: true)
        return Self(manifest: manifest, root: root, download: downloadAsset)
    }

    static func downloadAsset(_ url: URL, _ limit: Int) async throws -> (URL, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return try await session.download(from: url, delegate: AssistantDDIDownloadLimit(limit: limit))
    }

    static func verify(_ url: URL, asset: AssistantDDIManifest.Asset) throws -> Bool {
        guard (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == asset.size else { return false }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            let data = try file.read(upToCount: 262_144) ?? Data()
            if data.isEmpty { break }
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == asset.sha256
    }

    func prepare(method: AssistantDDIMethod, progress: @escaping (String) -> Void) async throws -> URL {
        let assets = try manifest.assets(for: method)
        let directory = root.appendingPathComponent(manifest.commit, isDirectory: true)
            .appendingPathComponent(method.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, asset) in assets.enumerated() {
            try Task.checkCancellation()
            progress("正在校验开发者映像 \(index + 1)/\(assets.count)…")
            let target = directory.appendingPathComponent(asset.name)
            if (try? Self.verify(target, asset: asset)) == true { continue }
            progress("正在下载开发者映像 \(index + 1)/\(assets.count)…")
            let (temporary, response) = try await download(URL(string: asset.url)!, asset.size)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.absoluteString == asset.url else { throw AssistantDDIError.response }
            guard try Self.verify(temporary, asset: asset) else { throw AssistantDDIError.integrity }
            // Stage on the same volume and publish one complete, verified file.
            let stage = directory.appendingPathComponent(UUID().uuidString + ".pending")
            defer { try? FileManager.default.removeItem(at: stage) }
            try FileManager.default.copyItem(at: temporary, to: stage)
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: stage)
            } else { try FileManager.default.moveItem(at: stage, to: target) }
        }
        return directory
    }
}
