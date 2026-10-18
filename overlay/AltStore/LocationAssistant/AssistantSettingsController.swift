import UIKit
import UniformTypeIdentifiers
import MinimuxerCommon
import Combine

final class AssistantSettingsController: UITableViewController, UIDocumentPickerDelegate {
    private let session = AssistantSession.shared
    private var observations = Set<AnyCancellable>()
    private var importing = false
    private lazy var certificateImporter = AssistantCertificateImporter(presenting: self)
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        session.$busy.sink { [weak self] _ in self?.tableView.reloadData() }.store(in: &observations)
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 12 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = ["导入本设备配对文件", "设备 IP", "检查定位连接", "安装与恢复指南", "脱敏诊断信息", "开源项目与许可证", "重启后确认真实位置已恢复", "导入续签证书", "登录服务", "检查登录服务", "重建登录认证缓存", "准备定位开发服务"][indexPath.row]
        if indexPath.row == 1 { cell.detailTextLabel?.text = session.deviceIP }
        if indexPath.row == 8 { cell.detailTextLabel?.text = AssistantLoginPolicy.serviceLabel }
        cell.textLabel?.textColor = session.busy || importing ? .secondaryLabel : .label
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !session.busy, !importing else { return }
        switch indexPath.row {
        case 0:
            if session.needsClear { show("请先清除模拟定位", "当前模拟状态尚未确认清除，先清除再更换配对文件。"); return }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.propertyList, .xml, .data], asCopy: true)
            picker.delegate = self
            present(picker, animated: true)
        case 1:
            if session.needsClear { show("请先清除模拟定位", "先清除模拟，再修改设备 IP。"); return }
            let alert = UIAlertController(title: "设备 IP", message: "填写 LocalDevVPN 的装置 IP，不带 /32。例如 10.7.0.1。", preferredStyle: .alert)
            alert.addTextField { $0.text = self.session.deviceIP; $0.keyboardType = .numbersAndPunctuation }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
                let value = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard let ip = AssistantIPv4.canonical(value) else {
                    self.show("IP 无效", "请输入完整 IPv4 地址，不要带斜杠或端口。"); return
                }
                self.session.deviceIP = ip
                self.tableView.reloadData()
            })
            present(alert, animated: true)
        case 2:
            if session.needsClear { show("请先清除模拟定位", "检查会建立新的连接，请先清除当前模拟。"); return }
            session.checkConnection { [weak self] message in self?.show("定位连接检查", message) }
        case 3:
            show("安装与恢复指南", "首次：电脑签名安装 → 开启开发者模式 → 导入本设备配对文件 → 连接 Wi-Fi 和 LocalDevVPN。\n\n使用：选点 → 开始模拟（自动检查及准备开发者映像） → 在地图 App 验证当前位置。\n\n结束：保持 VPN 连接 → 清除模拟定位 → 地图重新定位 → 再关闭 VPN。清除失败可重试；仍失败则关闭 VPN、重启设备，先验证真实位置。\n\n续签：在到期前手动刷新。每台设备分别签名和配对。")
        case 4:
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
            show("脱敏诊断", "App：\(version)\n系统：\(UIDevice.current.systemVersion)\n设备类型：\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")\n操作进行中：\(session.busy ? "是" : "否")\n可能遗留模拟：\(session.needsClear ? "是" : "否")\n\n最近失败：\n\(session.lastDiagnostic)\n\n不包含账号、UDID、配对内容、IP 或位置收藏。")
        case 5:
            show("开源声明", "基于 SideStore 0.7.0-alpha 与 StikDebug 3.1.13，保留 AGPL-3.0 许可证及原作者声明。\n\nSideStore：github.com/SideStore/SideStore\nStikDebug：github.com/StikDebug/StikDebug\n\n对应源码与依赖说明随安装包提供，详见仓库 THIRD_PARTY_NOTICES.md。")
        case 6:
            guard session.needsClear else { show("无需重置", "当前没有遗留模拟的记录。"); return }
            guard session.activeCoordinate == nil else { show("模拟仍在运行", "请先点击定位页的清除模拟定位。"); return }
            let alert = UIAlertController(title: "仅用于重启后恢复", message: "此操作只重置本 App 的未知状态记录，不会清除系统定位。只有已重启设备，并在地图 App 中确认真实位置恢复后，才可继续。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "我已重启并确认恢复", style: .default) { _ in self.session.acknowledgeRecoveryAfterRestart() })
            present(alert, animated: true)
        case 7:
            if session.needsClear { show("请先清除模拟定位", "清除模拟后再导入续签证书。"); return }
            certificateImporter.start()
        case 8:
            let alert = UIAlertController(title: "登录服务", message: "从所选服务读取匹配配置。Apple 账号密码只提交给 Apple；证书与配对不发给认证服务。服务检查成功不能保证 Apple 登录成功。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "自动选择", style: .default) { _ in
                UserDefaults.standard.set(false, forKey: AssistantLoginPolicy.originalServiceKey)
                UserDefaults.standard.removeObject(forKey: AssistantLoginPolicy.selectedServiceKey)
                Task { await AssistantLoginService.shared.clearMemoryCache() }
                self.tableView.reloadData()
            })
            for address in AssistantLoginPolicy.allServiceURLs {
                alert.addAction(UIAlertAction(title: URL(string: address)?.host ?? address, style: .default) { _ in
                    UserDefaults.standard.set(false, forKey: AssistantLoginPolicy.originalServiceKey)
                    UserDefaults.standard.set(address, forKey: AssistantLoginPolicy.selectedServiceKey)
                    Task { await AssistantLoginService.shared.clearMemoryCache() }
                    self.tableView.reloadData()
                })
            }
            alert.addAction(UIAlertAction(title: "使用原有配置", style: .default) { _ in
                UserDefaults.standard.set(true, forKey: AssistantLoginPolicy.originalServiceKey)
                self.tableView.reloadData()
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            present(alert, animated: true)
        case 9, 10:
            guard AssistantLoginPolicy.usesCompatibleService else {
                show("当前使用原有配置", "内置服务检查与缓存重建只适用于内置登录服务。请先在登录服务中选择自动选择或指定服务，再执行本项检查。")
                return
            }
            if session.needsClear { show("请先清除模拟定位", "清除模拟后再检查或重建登录服务缓存。"); return }
            guard session.beginMaintenance() else { return }
            Task {
                do {
                    if indexPath.row == 9 { try await AssistantLoginService.shared.checkService() }
                    else { try await AssistantLoginService.shared.resetCache() }
                    session.endMaintenance()
                    if indexPath.row == 9 {
                        show("登录服务可连接", "已读取有效客户端配置。尚未验证 Apple 账号，也尚未续签；请返回续签页登录。")
                    } else { show("登录认证缓存已重建", "未修改 Apple 账号、签名证书、配对或收藏。请返回续签页登录。") }
                } catch {
                    session.endMaintenance()
                    session.recordFailure(stage: "登录服务检查", error: error)
                    show("登录服务未就绪", AssistantSession.safeError(error))
                }
            }
        case 11:
            if session.needsClear { show("请先清除模拟定位", "若清除时需要开发者映像，会自动准备；当前请先在定位页清除模拟。"); return }
            session.prepareDeveloperServices()
            show("正在准备开发服务", "请保持 App 在前台。准备状态显示在定位页和续签页；首次缺少映像时需要联网下载约 17 MB。此操作不提交模拟位置，也不验证 Apple 登录。")
        default: break
        }
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, !importing, session.beginMaintenance() else { return }
        importing = true
        tableView.reloadData()
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= 2_000_000 else { throw CocoaError(.fileReadTooLarge) }
                let data = try Data(contentsOf: url)
                let snapshot = try AssistantPairingPolicy.normalize(data,
                    expectedUDID: Bundle.main.object(forInfoDictionaryKey: "ALTDeviceID") as? String)
                _ = try PairingFileParser.parse(content: snapshot.content)
                try PairingFileManager.shared.savePairingFile(contents: snapshot.content)
                DispatchQueue.main.async {
                    self.importing = false
                    self.session.endMaintenance()
                    self.tableView.reloadData()
                    self.show("配对文件已保存", snapshot.kind == .remote
                        ? "已保存远程配对文件。下次定位或续签会读取新文件，无需重新导入证书。请检查定位连接。"
                        : "已保存传统配对文件，可供续签使用。当前定位模块需要远程配对文件；请用 iloader 获取本设备的远程配对后再使用定位。")
                }
            } catch {
                DispatchQueue.main.async {
                    self.importing = false
                    self.session.endMaintenance()
                    self.tableView.reloadData()
                    self.show("导入失败", (error as? AssistantPairingError)?.localizedDescription ?? "文件无法读取或格式不正确。请用 iloader 为本设备重新生成配对文件。")
                }
            }
        }
    }
    private func show(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}
