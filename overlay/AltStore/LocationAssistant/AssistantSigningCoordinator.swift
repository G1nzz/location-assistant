import UIKit
import Combine
import SideSign
import MinimuxerCommon

// Signing is opt-in and does not own the location status or location-page startup.
@MainActor
final class AssistantSigningCoordinator: ObservableObject {
    static let shared = AssistantSigningCoordinator()
    @Published private(set) var status = "尚未验证签名账号；定位功能可单独使用"
    @Published private(set) var working = false
    @Published private(set) var expiration: Date?
    @Published private(set) var profileRead = false
    @Published private(set) var hasPrivateKey = false
    private var runtimeStarted = false
    private var loadingProfile = false
    private var progressObservation: NSKeyValueObservation?
    private var refreshGroup: RefreshGroup?
    private let session = AssistantSession.shared

    func reloadInstalledSignature() {
        guard !loadingProfile else { return }
        loadingProfile = true
        let url = Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")
        Task {
            let snapshot = await Task.detached(priority: .utility) {
                let expiry = (try? ALTProvisioningProfile(url: url))?.expirationDate
                let ownsKey = CertificateManager.shared.activeCertificate.map { !$0.certificate.privateKey.isEmpty } ?? false
                return (expiry, ownsKey)
            }.value
            expiration = snapshot.0
            hasPrivateKey = snapshot.1
            profileRead = true
            loadingProfile = false
        }
    }

    private func prepareRuntime() async throws {
        status = "正在准备本设备续签记录…"
        try await DatabaseManager.shared.start()
        guard let pairing = PairingFileManager.shared.fetchPairingFile() else { throw OperationError.invalidPairingFile() }
        _ = try PairingFileParser.parse(content: pairing)
        if !runtimeStarted {
            status = "正在连接本设备续签服务…"
            try await AppBootManager.shared.startMinimuxer(pairingFile: pairing)
            runtimeStarted = true
        }
    }

    func signIn(presenting controller: UIViewController) {
        guard !working, session.beginMaintenance() else { return }
        working = true
        status = "正在准备签名账号验证…"
        Task {
            do {
                try await prepareRuntime()
                status = "正在验证 Apple 签名账号；请完成弹出的登录与验证码提示"
                _ = try await AuthManager.shared.signIn(presentingViewController: controller)
                status = "账号与证书验证完成；尚未刷新自身签名"
            } catch { fail(stage: "签名账号验证", error: error) }
            working = false
            session.endMaintenance()
            reloadInstalledSignature()
        }
    }

    func refresh(presenting controller: UIViewController) {
        guard !working else { return }
        session.prepareForRefresh { [weak self, weak controller] ready in
            guard let self else { return }
            guard ready, let controller else {
                if ready { self.session.endMaintenance() }
                else { self.status = "未开始续签：\(self.session.status)" }
                return
            }
            self.working = true
            self.status = "模拟连接已释放，正在准备续签…"
            Task {
                do {
                    try await self.prepareRuntime()
                    guard let app = InstalledApp.fetchAltStore(in: DatabaseManager.shared.viewContext) else { throw OperationError.appNotFound(name: "定位助手") }
                    self.status = "正在刷新自身签名…"
                    let group = AppManager.shared.refreshSelfForAssistant(app, presentingViewController: controller) { [weak self] result in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            self.progressObservation = nil
                            self.refreshGroup = nil
                            self.working = false
                            self.session.endMaintenance()
                            switch result {
                            case .success: self.status = "续签流程完成；重新打开 App 后核对当前安装包到期时间"
                            case .failure(let error): self.fail(stage: "自身续签", error: error)
                            }
                            self.reloadInstalledSignature()
                        }
                    }
                    self.refreshGroup = group
                    self.progressObservation = group.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
                        let percent = min(100, max(0, Int(progress.fractionCompleted * 100)))
                        DispatchQueue.main.async {
                            guard let self, self.refreshGroup != nil else { return }
                            self.status = "正在刷新自身签名：\(percent)%"
                        }
                    }
                } catch {
                    self.working = false
                    self.session.endMaintenance()
                    self.fail(stage: "续签准备", error: error)
                }
            }
        }
    }

    private func fail(stage: String, error: Error) {
        status = "\(stage)失败：\(AssistantSession.safeError(error))"
        session.recordFailure(stage: stage, error: error)
    }
}
