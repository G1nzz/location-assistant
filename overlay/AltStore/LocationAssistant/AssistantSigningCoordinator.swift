import UIKit
import Combine
import SideSign
import MinimuxerCommon
import Minimuxer

// Signing is opt-in and does not own the location status or location-page startup.
@MainActor
final class AssistantSigningCoordinator: ObservableObject {
    static let shared = AssistantSigningCoordinator()
    @Published private(set) var status: String
    @Published private(set) var working = false
    @Published private(set) var expiration: Date?
    @Published private(set) var profileRead = false
    @Published private(set) var hasPrivateKey = false
    @Published private(set) var privateKeyStatus = "正在读取本设备签名私钥…"
    @Published private(set) var accountStatus = "正在读取本设备登录凭据…"
    @Published private(set) var lastReceipt: AssistantSigningHistory.Receipt?
    private var loadingProfile = false
    private var databasePrepared = false
    private var progressObservation: NSKeyValueObservation?
    private var refreshGroup: RefreshGroup?
    private let session = AssistantSession.shared
    private var history: AssistantSigningHistory

    private init() {
        let saved = AssistantSigningHistory.load()
        history = saved
        status = saved.summary
        lastReceipt = saved.receipt
    }

    private func record(_ kind: AssistantSigningHistory.Kind, message: String? = nil, expiration: Date? = nil) {
        history.record(kind, message: message, expiration: expiration)
        lastReceipt = history.receipt
    }

    func certificateImported() {
        record(.certificateSaved)
        status = "续签证书已保存；请验证该证书所属的 Apple 签名账号"
        reloadInstalledSignature()
    }

    func reloadInstalledSignature() {
        guard !loadingProfile else { return }
        loadingProfile = true
        let url = Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")
        Task {
            let snapshot = await Task.detached(priority: .utility) {
                let expiry = (try? ALTProvisioningProfile(url: url))?.expirationDate
                let keyResult = Result {
                    try AssistantLocalKeychain.migrateIfNeeded()
                    let saved = try CertificateManager.shared.loadActiveCertificate()
                    return saved.map { !$0.certificate.privateKey.isEmpty } ?? false
                }
                let loginResult = Result {
                    let email = try AssistantLocalKeychain.read("appleIDEmailAddress")
                    let token = try AssistantLocalKeychain.read("appleIDXcodeToken")
                    let password = try AssistantLocalKeychain.read("appleIDPassword")
                    return email != nil && (token != nil || password != nil)
                }
                return (expiry, keyResult, loginResult)
            }.value
            expiration = snapshot.0
            switch snapshot.1 {
            case .success(let ownsKey):
                hasPrivateKey = ownsKey
                privateKeyStatus = ownsKey ? "已保存；续签时还会核对证书是否有效" : "未找到签名私钥，请在设置中导入完整 .p12/.pfx 文件"
            case .failure(let error):
                hasPrivateKey = false
                privateKeyStatus = "私钥读取失败：\(AssistantSession.safeError(error))"
                session.recordFailure(stage: "读取签名私钥", error: error)
            }
            switch snapshot.2 {
            case .success(let saved):
                accountStatus = saved ? "已保存本设备登录凭据；会话有效性仍需向 Apple 验证" : "未找到本设备登录凭据，请登录或验证签名账号"
            case .failure(let error):
                accountStatus = "登录凭据读取失败：\(AssistantSession.safeError(error))"
                session.recordFailure(stage: "读取签名凭据", error: error)
            }
            profileRead = true
            loadingProfile = false
        }
    }

    private func prepareDatabase() async throws {
        try await DatabaseManager.shared.start()
        if !databasePrepared {
            await Task.detached(priority: .utility) {
                AppDelegate.reconcileSelfReinstallationIfNeeded()
                // Do not run upstream maintenance here. Its first legacy pass
                // clears the keychain, including a certificate imported before
                // this lazily initialized signing database was ever opened.
            }.value
            databasePrepared = true
        }
    }

    private func prepareRuntime() async throws {
        status = "正在准备本设备续签记录…"
        try await prepareDatabase()
        guard let pairing = PairingFileManager.shared.fetchPairingFile() else { throw OperationError.invalidPairingFile() }
        _ = try AssistantPairingPolicy.normalize(Data(pairing.utf8), expectedUDID: Bundle.main.object(forInfoDictionaryKey: "ALTDeviceID") as? String)
        status = "正在连接本设备续签服务…"
        // A changed pairing file/IP or a prior failed connection must not reuse a
        // cached `started` flag. Stop the old proxy and initialize current inputs.
        try await minimuxer.core.stop()
        try await AppBootManager.shared.startMinimuxer(pairingFile: pairing)
    }

    func signIn(presenting controller: UIViewController) {
        guard !working, session.beginMaintenance() else { return }
        working = true
        status = "正在准备签名账号验证…"
        record(.accountStarted)
        Task {
            do {
                try await prepareDatabase()
                status = "正在验证 Apple 签名账号；请完成弹出的登录与验证码提示"
                // Account verification neither requires a device tunnel nor starts
                // registration, certificate replacement or a forced reinstall.
                _ = try await AuthManager.shared.signIn(presentingViewController: controller,
                    skipDeviceRegistration: true, skipCertificateProvisioning: true)
                status = "账号验证完成；证书有效性与实际续签尚未验证"
                record(.accountVerified)
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
            self.record(.refreshStarted)
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
                            switch result {
                            case .success(let refreshedApp):
                                // The result belongs to its Core Data context.
                                // Fast refresh installs profiles without rewriting
                                // the app's embedded.mobileprovision.
                                Task {
                                    let expiry = await refreshedApp.managedObjectContext?.perform { refreshedApp.expirationDate }
                                    self.record(.refreshAccepted, expiration: expiry)
                                    self.status = self.history.summary
                                    self.working = false
                                    self.session.endMaintenance()
                                    self.reloadInstalledSignature()
                                }
                            case .failure(let error):
                                self.fail(stage: "自身续签", error: error)
                                self.working = false
                                self.session.endMaintenance()
                                self.reloadInstalledSignature()
                            }
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
        let message = AssistantSession.safeError(error)
        record(stage == "签名账号验证" ? .accountFailed : .refreshFailed, message: message)
        status = "\(stage)失败：\(message)"
        session.recordFailure(stage: stage, error: error)
    }
}
