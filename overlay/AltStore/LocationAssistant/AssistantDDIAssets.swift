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
    case manifest, response(Int?), integrity, sizeLimit, native(Int32)
    var errorDescription: String? {
        switch self {
        case .manifest: return "本版开发者映像配置无效，请保留 App 数据并更新安装包。"
        case .response(let status): return "下载服务器响应异常\(status.map { "（HTTP \($0)）" } ?? "")，请检查网络后重试提前下载映像。"
        case .integrity: return "开发者映像大小或校验值不符，已拒绝使用；请重试下载。"
        case .sizeLimit: return "下载大小超过固定映像清单的限制，已中止下载；请检查下载响应后重试。"
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
    private let lock = NSLock()
    private var exceeded = false
    var exceededLimit: Bool { lock.lock(); defer { lock.unlock() }; return exceeded }
    init(limit: Int) { self.limit = Int64(limit) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit {
            lock.lock(); exceeded = true; lock.unlock()
            downloadTask.cancel()
        }
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
        do {
        guard let file = Bundle.main.url(forResource: "AssistantDDIManifest", withExtension: "json") else {
            throw AssistantDDIError.manifest
        }
        let manifest = try JSONDecoder().decode(AssistantDDIManifest.self, from: Data(contentsOf: file))
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AssistantDDI", isDirectory: true)
        return Self(manifest: manifest, root: root, download: downloadAsset)
        } catch { throw AssistantDDIFailure.convert(error, stage: .configuration) }
    }

    static func downloadAsset(_ url: URL, _ limit: Int) async throws -> (URL, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let limiter = AssistantDDIDownloadLimit(limit: limit)
        let result: (URL, URLResponse)
        do { result = try await session.download(from: url, delegate: limiter) }
        catch {
            if limiter.exceededLimit { throw AssistantDDIError.sizeLimit }
            throw error
        }
        let (temporary, response) = result
        guard !limiter.exceededLimit else {
            try? FileManager.default.removeItem(at: temporary)
            throw AssistantDDIError.sizeLimit
        }
        // Own the file before invalidating the temporary download session.
        let owned = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-ddi-" + UUID().uuidString)
        do { try FileManager.default.moveItem(at: temporary, to: owned) }
        catch { throw AssistantDDIFailure.convert(error, stage: .cacheCommit) }
        return (owned, response)
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
        let assets: [AssistantDDIManifest.Asset]
        do { assets = try manifest.assets(for: method) }
        catch { throw AssistantDDIFailure.convert(error, stage: .configuration) }
        let directory = root.appendingPathComponent(manifest.commit, isDirectory: true)
            .appendingPathComponent(method.rawValue, isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { throw AssistantDDIFailure.convert(error, stage: .cacheDirectory) }
        for (index, asset) in assets.enumerated() {
            try Task.checkCancellation()
            progress("正在校验开发者映像 \(index + 1)/\(assets.count)…")
            let target = directory.appendingPathComponent(asset.name)
            do { if try Self.verify(target, asset: asset) { continue } }
            catch is CancellationError { throw CancellationError() }
            catch { /* Unreadable/corrupt cache is replaced only after verification. */ }
            progress("正在下载开发者映像 \(index + 1)/\(assets.count)…")
            let result: (URL, URLResponse)
            do { result = try await download(URL(string: asset.url)!, asset.size) }
            catch { throw AssistantDDIFailure.convert(error, stage: .download, asset: asset.name) }
            let (temporary, response) = result
            defer { try? FileManager.default.removeItem(at: temporary) }
            try Task.checkCancellation()
            do {
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.url?.absoluteString == asset.url else {
                    throw AssistantDDIError.response((response as? HTTPURLResponse)?.statusCode)
                }
            } catch { throw AssistantDDIFailure.convert(error, stage: .download, asset: asset.name) }
            do {
                guard try Self.verify(temporary, asset: asset) else { throw AssistantDDIError.integrity }
            } catch { throw AssistantDDIFailure.convert(error, stage: .verification, asset: asset.name) }
            // Stage on the same volume and publish one complete, verified file.
            let stage = directory.appendingPathComponent(UUID().uuidString + ".pending")
            defer { try? FileManager.default.removeItem(at: stage) }
            do {
                try FileManager.default.copyItem(at: temporary, to: stage)
                if FileManager.default.fileExists(atPath: target.path) {
                    _ = try FileManager.default.replaceItemAt(target, withItemAt: stage)
                } else { try FileManager.default.moveItem(at: stage, to: target) }
            } catch { throw AssistantDDIFailure.convert(error, stage: .cacheCommit, asset: asset.name) }
        }
        return directory
    }
}
