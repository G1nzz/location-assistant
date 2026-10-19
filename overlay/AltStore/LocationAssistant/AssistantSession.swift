import UIKit
import CoreLocation
import Combine
import SideSign

@MainActor
final class AssistantSession: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = AssistantSession()
    @Published private(set) var busy = false
    @Published private(set) var status = "尚未模拟定位"
    @Published private(set) var activeCoordinate: CLLocationCoordinate2D?
    @Published private(set) var needsClear: Bool
    private let locationManager = CLLocationManager()
    private var keepAlive: DispatchSourceTimer?
    private var keepAliveTicket: AssistantCommandTicket?
    private var generation = 0
    private let workQueue = DispatchQueue(label: "locationassistant.commands", qos: .userInitiated)
    private var preparationTask: Task<Void, Never>?
    private let persistenceKey = "assistant.needsClear"

    private override init() {
        needsClear = UserDefaults.standard.bool(forKey: "assistant.needsClear")
        super.init()
        synchronizeSigningConnection()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = CLLocationDistanceMax
        locationManager.allowsBackgroundLocationUpdates = true
        // The simulated position is stationary by definition. Automatic pausing
        // would suspend the process and its iOS 26 keepalive timer. Updates are
        // explicitly stopped on clear/failure and only run during simulation.
        locationManager.pausesLocationUpdatesAutomatically = false
        if needsClear { status = "上次模拟可能仍有效，请先清除模拟定位" }
        NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    var deviceIP: String {
        get { UserDefaults.standard.string(forKey: "assistant.deviceIP") ?? "10.7.0.1" }
        set {
            UserDefaults.standard.set(newValue, forKey: "assistant.deviceIP")
            synchronizeSigningConnection()
        }
    }

    private func synchronizeSigningConnection() {
        ConnectionConfig.shared.useLocalVPN = true
        ConnectionConfig.shared.overrideTunnelPeerIp = deviceIP
        ConnectionConfig.shared.remoteServerIp = deviceIP
    }

    func beginMaintenance() -> Bool {
        guard !busy, !needsClear else { return false }
        busy = true
        return true
    }
    func endMaintenance() { busy = false }

    func acknowledgeRecoveryAfterRestart() {
        guard !busy, activeCoordinate == nil else { return }
        busy = true
        generation += 1
        stopKeepAlive()
        locationManager.stopUpdatingLocation()
        workQueue.async {
            AssistantNative.disconnect()
            DispatchQueue.main.async {
                self.setNeedsClear(false)
                self.busy = false
                self.status = "已记录你在重启后确认真实位置恢复；本 App 未自动验证"
            }
        }
    }

    private func native(_ operation: @escaping () -> Int32) async -> Int32 {
        await withCheckedContinuation { continuation in
            workQueue.async { continuation.resume(returning: operation()) }
        }
    }

    private func prepareDeveloperServices(ip: String) async throws {
        let method = AssistantDDIMethod.current
        status = "正在检查本设备开发服务…"
        let code = await native { AssistantNative.ddiStatus(ip: ip, method: method) }
        try Task.checkCancellation()
        if code == 0 { return }
        guard code == 20 else { throw AssistantDDIError.native(code) }
        let directory = try await downloadDeveloperImages(method: method)
        try Task.checkCancellation()
        status = "正在挂载开发者映像，请保持 App 在前台…"
        let result = await native { AssistantNative.mountDDI(ip: ip, method: method, directory: directory) }
        try Task.checkCancellation()
        guard result == 0 else { throw AssistantDDIError.native(result) }
    }

    // This path intentionally has no device connection, account or certificate
    // prerequisite. Complete it on a reachable network before changing VPN.
    private func downloadDeveloperImages(method: AssistantDDIMethod) async throws -> URL {
        let ticket = generation
        let download = Task.detached(priority: .utility) {
            let assets = try AssistantDDIAssets.installed()
            return try await assets.prepare(method: method) { message in
                Task { @MainActor in
                    guard self.busy, self.generation == ticket, self.preparationTask != nil else { return }
                    self.status = message
                }
            }
        }
        return try await withTaskCancellationHandler {
            try await download.value
        } onCancel: { download.cancel() }
    }

    func downloadDeveloperImages() {
        // Cache-only work is safe while a previous simulated position is
        // unknown. Do not force a successful clear before downloading the
        // resources that clear may itself need. Block an actively held session.
        guard !busy, activeCoordinate == nil else { return }
        busy = true
        generation += 1
        let method = AssistantDDIMethod.current
        status = "正在准备提前下载映像…"
        preparationTask = Task {
            defer { busy = false; preparationTask = nil }
            do {
                _ = try await downloadDeveloperImages(method: method)
                try Task.checkCancellation()
                status = needsClear
                    ? "映像文件已下载并校验；请切换到 LocalDevVPN，再到定位页清除遗留模拟。未知模拟记录仍保留。"
                    : "映像文件已下载并校验；现在可切换到 LocalDevVPN，再到设置准备定位开发服务。尚未挂载或模拟定位。"
            } catch { preparationFailed(error) }
        }
    }

    func prepareDeveloperServices() {
        guard beginMaintenance() else { return }
        generation += 1
        let ip = deviceIP
        preparationTask = Task {
            defer { busy = false; preparationTask = nil }
            do {
                try await prepareDeveloperServices(ip: ip)
                status = "开发者映像已确认挂载；尚未模拟定位，也尚未验证续签"
            } catch { preparationFailed(error) }
        }
    }

    private func preparationFailed(_ error: Error) {
        activeCoordinate = nil
        locationManager.stopUpdatingLocation()
        let message: String
        let diagnostic: String
        if error is CancellationError {
            message = "准备已取消，请保持 App 在前台；下载完成后再切换 VPN"
            diagnostic = "阶段：开发者映像处理\n结果：操作取消"
        } else if let failure = error as? AssistantDDIFailure {
            message = failure.localizedDescription
            diagnostic = failure.diagnostic
        } else if let ddi = error as? AssistantDDIError {
            if case .native(let code) = ddi {
                message = code < 20 ? Self.failure(code) : ddi.localizedDescription
                diagnostic = "阶段：开发者服务连接/挂载\n原生阶段代码：\(code)\n" + message
            } else {
                message = ddi.localizedDescription
                diagnostic = "阶段：开发者映像处理\n" + message
            }
        } else {
            let failure = AssistantDDIFailure(stage: .preparation, error: error)
            message = failure.localizedDescription
            diagnostic = failure.diagnostic
        }
        status = message + (needsClear ? "；原模拟可能仍有效，结束时仍需清除。" : "")
        UserDefaults.standard.set(diagnostic, forKey: "assistant.lastFailure")
    }

    @objc private func enteredBackground() {
        // Downloads are cancellable. A synchronous FFI mount cannot be safely
        // interrupted; after it returns cancellation prevents submitting a point.
        preparationTask?.cancel()
    }

    func start(_ coordinate: CLLocationCoordinate2D) {
        guard !busy, AssistantCoordinate.valid(coordinate) else { return }
        busy = true
        generation += 1
        stopKeepAlive()
        let ip = deviceIP
        preparationTask = Task {
            defer { busy = false; preparationTask = nil }
            do {
                try await prepareDeveloperServices(ip: ip)
                let connected = await native { AssistantNative.connect(ip: ip) }
                try Task.checkCancellation()
                guard connected == 0 else { throw AssistantDDIError.native(connected) }
                // DDI/connection failures must not create a simulated-position
                // intent. Persist only immediately before a position command.
                setNeedsClear(true)
                let result = await native { AssistantNative.set(ip: ip, coordinate: coordinate) }
                if result == 0 {
                    activeCoordinate = coordinate
                    status = "模拟位置已提交，可切换到地图 App 验证"
                    startBackgroundSupport()
                    startKeepAlive(coordinate)
                } else {
                    status = Self.failure(result)
                    recordNativeFailure(stage: "开始模拟", code: result)
                    activeCoordinate = nil
                    locationManager.stopUpdatingLocation()
                }
            } catch {
                _ = await native { AssistantNative.disconnect(); return 0 }
                preparationFailed(error)
            }
        }
    }

    func clear(completion: ((Bool) -> Void)? = nil) {
        guard !busy else { completion?(false); return }
        busy = true
        generation += 1
        stopKeepAlive()
        locationManager.stopUpdatingLocation()
        let ip = deviceIP
        preparationTask = Task {
            defer { preparationTask = nil }
            do {
                try await prepareDeveloperServices(ip: ip)
                try Task.checkCancellation()
                status = "正在清除系统模拟定位…"
                let result = await native { AssistantNative.clear(ip: ip) }
                activeCoordinate = nil
                if result == 0 {
                    setNeedsClear(false)
                    status = "清除请求成功，请在地图中重新获取当前位置"
                } else {
                    setNeedsClear(true)
                    recordNativeFailure(stage: "清除模拟", code: result)
                    status = "清除失败（\(result)）。保持 LocalDevVPN 连接后重试；仍失败请关闭 VPN、重启设备，暂勿重新开启模拟。"
                }
                // Release busy before callback: refresh may acquire it here.
                busy = false
                completion?(result == 0)
            } catch {
                _ = await native { AssistantNative.disconnect(); return 0 }
                preparationFailed(error)
                busy = false
                completion?(false)
            }
        }
    }

    func prepareForRefresh(completion: @escaping (Bool) -> Void) {
        guard !busy else { completion(false); return }
        if needsClear {
            clear { success in
                if success { self.busy = true; completion(true) }
                else { completion(false) }
            }
        } else {
            busy = true
            generation += 1
            stopKeepAlive()
            workQueue.async {
                AssistantNative.disconnect()
                DispatchQueue.main.async { completion(true) }
            }
        }
    }

    func checkConnection(completion: @escaping (String) -> Void) {
        guard !busy, !needsClear else { return }
        busy = true
        let ip = deviceIP
        workQueue.async {
            let code = AssistantNative.check(ip: ip)
            DispatchQueue.main.async {
                self.busy = false
                self.status = code == 0 ? "定位服务连接成功；续签连接会在刷新时另行检查" : Self.failure(code)
                if code != 0 { self.recordNativeFailure(stage: "定位连接检查", code: code) }
                completion(self.status)
            }
        }
    }

    private func setNeedsClear(_ value: Bool) {
        needsClear = value
        UserDefaults.standard.set(value, forKey: persistenceKey)
    }

    private func startBackgroundSupport() {
        switch locationManager.authorizationStatus {
        case .notDetermined: locationManager.requestAlwaysAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: locationManager.startUpdatingLocation()
        default: status = "位置已提交，但未获后台定位权限；后台连接可能中断"
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard activeCoordinate != nil else { return }
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        } else {
            status = "后台定位权限未开启，连接可能中断；模拟位置仍可能有效"
        }
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        guard !busy, activeCoordinate != nil else { return }
        status = "后台保活被系统暂停；模拟位置可能仍有效。请返回本页检查连接，结束时仍需清除模拟。"
    }

    private func startKeepAlive(_ coordinate: CLLocationCoordinate2D) {
        // StikDebug resubmits static location for iOS 26. Retain that compatibility behavior,
        // but never poll UI/search. The serial timer cannot queue overlapping native calls.
        guard #available(iOS 26.0, *) else { return }
        let token = generation, ip = deviceIP
        let ticket = AssistantCommandTicket()
        keepAliveTicket = ticket
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + 4, repeating: 4, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard !ticket.isCancelled else { return }
            let code = AssistantNative.set(ip: ip, coordinate: coordinate)
            if code != 0 {
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    self.stopKeepAlive()
                    self.activeCoordinate = nil
                    self.locationManager.stopUpdatingLocation()
                    self.recordNativeFailure(stage: "后台定位连接", code: code)
                    self.status = "定位连接中断（\(code)）；系统可能仍保留模拟位置，请清除后重试"
                }
            }
        }
        keepAlive = timer
        timer.resume()
    }

    private func stopKeepAlive() {
        keepAliveTicket?.cancel()
        keepAliveTicket = nil
        keepAlive?.cancel()
        keepAlive = nil
    }

    @objc private func becameActive() {
        guard !busy, let coordinate = activeCoordinate else { return }
        // A suspended process cannot establish continuous connectivity. Verify on return.
        start(coordinate)
    }

    static func failure(_ code: Int32) -> String {
        switch code {
        case 1: return "设备 IP 无效，请填写 IPv4 地址，不要带 /32"
        case 2: return "配对文件缺失或无效，请导入本设备的配对文件"
        case 3: return "设备连接失败，请检查 Wi-Fi、LocalDevVPN 和配对文件"
        case 4: return "当前是传统配对文件：可供续签使用，但定位模块需要本设备的远程配对文件。"
        case 5: return "远程配对更新无法保存，已停止提交新位置。请检查设备空间与配对文件，再重试或清除模拟。"
        case 20...25: return AssistantDDIStatus.message(code)
        case 9, 10: return "定位服务连接失败（\(code)），请检查开发者模式及系统兼容性"
        default: return "定位命令失败（\(code)）；模拟状态未知，请尝试清除"
        }
    }

    var lastDiagnostic: String { UserDefaults.standard.string(forKey: "assistant.lastFailure") ?? "尚未记录失败" }

    private func recordNativeFailure(stage: String, code: Int32) {
        UserDefaults.standard.set("阶段：\(stage)\n定位错误代码：\(code)\n\(Self.failure(code))", forKey: "assistant.lastFailure")
    }

    func recordFailure(stage: String, error: Error) {
        UserDefaults.standard.set("阶段：\(stage)\n\(Self.safeError(error))", forKey: "assistant.lastFailure")
    }

    static func safeError(_ error: Error) -> String {
        if let failure = error as? AssistantDDIFailure { return failure.localizedDescription }
        if let ddi = error as? AssistantDDIError { return ddi.localizedDescription }
        if let pairingError = error as? AssistantPairingError { return pairingError.localizedDescription }
        if let certificateError = error as? AssistantCertificateError { return certificateError.localizedDescription }
        if let loginError = error as? AssistantLoginError { return loginError.localizedDescription }
        if error is CancellationError { return "操作已取消" }
        if let serverError = error as? SideSign.ServerError,
           case .underlyingError(let code, _) = serverError {
            return AssistantErrorPresentation.describe(domain: "SideSign.DeveloperPortalError", code: code)
        }
        if let operation = error as? OperationError {
            switch operation {
            case .unknownUDID, .invalidPairingFile, .pairingNotComplete:
                return "本设备配对缺失或无效。请核对配对文件；无需重新导入签名证书。"
            case .noVPN, .invalidVPN, .noDevice, .notReachable, .minimuxerNotStarted:
                return "续签的设备连接未就绪。请检查 Wi-Fi、LocalDevVPN 及本设备配对；登录服务检查不能代替此连接检查。"
            case .noConnection: return "续签前需要连接 Wi-Fi，并连接 LocalDevVPN。"
            case .certificateRevoked, .certificateExpired, .certificateChanged:
                return "当前安装签名与有效签名证书不一致或已失效。请保留 App 和数据，使用电脑覆盖签名安装；不会自动撤销证书。"
            default: break
            }
        }
        let ns = error as NSError
        let authenticationCode = AssistantFailureClassifier.authenticationCode(in: ns)
        return AssistantErrorPresentation.describe(domain: ns.domain, code: ns.code, authenticationCode: authenticationCode)
    }
}
