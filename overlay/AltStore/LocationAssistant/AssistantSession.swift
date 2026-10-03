import UIKit
import CoreLocation
import Combine

@MainActor
final class AssistantSession: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = AssistantSession()
    @Published private(set) var busy = false
    @Published private(set) var status = "尚未模拟定位"
    @Published private(set) var activeCoordinate: CLLocationCoordinate2D?
    @Published private(set) var needsClear: Bool
    private let locationManager = CLLocationManager()
    private var progressObservation: NSKeyValueObservation?
    private var refreshGroup: RefreshGroup?
    private var keepAlive: DispatchSourceTimer?
    private var generation = 0
    private let workQueue = DispatchQueue(label: "locationassistant.commands", qos: .userInitiated)
    private let persistenceKey = "assistant.needsClear"

    private override init() {
        needsClear = UserDefaults.standard.bool(forKey: "assistant.needsClear")
        super.init()
        synchronizeSigningConnection()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = CLLocationDistanceMax
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = true
        if needsClear { status = "上次模拟可能仍有效，请先清除模拟定位" }
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

    func start(_ coordinate: CLLocationCoordinate2D) {
        guard !busy, AssistantCoordinate.valid(coordinate) else { return }
        busy = true
        status = "正在连接并提交位置…"
        generation += 1
        stopKeepAlive()
        let ip = deviceIP
        // Persist intent before the command: a lost reply must not imply that nothing happened.
        setNeedsClear(true)
        workQueue.async {
            let result = AssistantNative.set(ip: ip, coordinate: coordinate)
            DispatchQueue.main.async {
                self.busy = false
                if result == 0 {
                    self.activeCoordinate = coordinate
                    self.status = "模拟位置已提交，可切换到地图 App 验证"
                    self.startBackgroundSupport()
                    self.startKeepAlive(coordinate)
                } else {
                    self.status = Self.failure(result)
                    self.activeCoordinate = nil
                    self.locationManager.stopUpdatingLocation()
                }
            }
        }
    }

    func clear(completion: ((Bool) -> Void)? = nil) {
        guard !busy else { completion?(false); return }
        busy = true
        generation += 1
        stopKeepAlive()
        locationManager.stopUpdatingLocation()
        status = "正在清除系统模拟定位…"
        let ip = deviceIP
        workQueue.async {
            let result = AssistantNative.clear(ip: ip)
            DispatchQueue.main.async {
                self.busy = false
                self.activeCoordinate = nil
                if result == 0 {
                    self.setNeedsClear(false)
                    self.status = "清除请求成功，请在地图中重新获取当前位置"
                } else {
                    self.setNeedsClear(true)
                    self.status = "清除失败（\(result)）。保持 LocalDevVPN 连接后重试；仍失败请关闭 VPN、重启设备，暂勿重新开启模拟。"
                }
                completion?(result == 0)
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

    func refreshSelf(presenting controller: UIViewController) {
        prepareForRefresh { ready in
            guard ready else { return }
            guard let app = InstalledApp.fetchAltStore(in: DatabaseManager.shared.viewContext) else {
                self.busy = false
                self.status = "尚未建立自身签名记录，请完成首次安装与账号登录后重试"
                return
            }
            self.status = "正在刷新自身签名…"
            let group = AppManager.shared.refreshSelfForAssistant(app, presentingViewController: controller) { result in
                DispatchQueue.main.async {
                    self.progressObservation = nil
                    self.refreshGroup = nil
                    self.busy = false
                    switch result {
                    case .success: self.status = "刷新流程完成，请重新打开 App 核对到期时间"
                    case .failure(let error): self.status = "续签失败：\(Self.safeError(error))"
                    }
                }
            }
            self.refreshGroup = group
            self.progressObservation = group.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
                let percent = Int(progress.fractionCompleted * 100)
                DispatchQueue.main.async {
                    if self.refreshGroup != nil { self.status = "正在刷新自身签名：\(percent)%" }
                }
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

    private func startKeepAlive(_ coordinate: CLLocationCoordinate2D) {
        // StikDebug resubmits static location for iOS 26. Retain that compatibility behavior,
        // but never poll UI/search. The serial timer cannot queue overlapping native calls.
        guard #available(iOS 26.0, *) else { return }
        let token = generation, ip = deviceIP
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + 4, repeating: 4, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            let code = AssistantNative.set(ip: ip, coordinate: coordinate)
            if code != 0 {
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    self.stopKeepAlive()
                    self.activeCoordinate = nil
                    self.locationManager.stopUpdatingLocation()
                    self.status = "定位连接中断（\(code)）；系统可能仍保留模拟位置，请清除后重试"
                }
            }
        }
        keepAlive = timer
        timer.resume()
    }

    private func stopKeepAlive() { keepAlive?.cancel(); keepAlive = nil }

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
        case 9, 10: return "定位服务连接失败（\(code)），请检查开发者模式及系统兼容性"
        default: return "定位命令失败（\(code)）；模拟状态未知，请尝试清除"
        }
    }

    static func safeError(_ error: Error) -> String {
        let ns = error as NSError
        if error is CancellationError { return "操作已取消" }
        // Native messages and auth failures can contain account or device identifiers.
        return "请检查网络、签名账号和配对文件（错误代码 \(ns.code)）"
    }
}
