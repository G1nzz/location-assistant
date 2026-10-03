import UIKit
import UniformTypeIdentifiers
import MinimuxerCommon
import Combine

final class AssistantSettingsController: UITableViewController, UIDocumentPickerDelegate {
    private let session = AssistantSession.shared
    private var observations = Set<AnyCancellable>()
    private var importing = false
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        session.$busy.sink { [weak self] _ in self?.tableView.reloadData() }.store(in: &observations)
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 6 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = ["导入本设备配对文件", "设备 IP", "检查定位连接", "安装与恢复指南", "脱敏诊断信息", "开源项目与许可证"][indexPath.row]
        if indexPath.row == 1 { cell.detailTextLabel?.text = session.deviceIP }
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
                let parts = value.split(separator: ".", omittingEmptySubsequences: false)
                guard parts.count == 4, parts.allSatisfy({ part in
                    !part.isEmpty && part.allSatisfy(\.isNumber) && (Int(part).map { (0...255).contains($0) } ?? false)
                }) else { self.show("IP 无效", "请输入完整 IPv4 地址，不要带斜杠或端口。"); return }
                self.session.deviceIP = value
                self.tableView.reloadData()
            })
            present(alert, animated: true)
        case 2:
            if session.needsClear { show("请先清除模拟定位", "检查会建立新的连接，请先清除当前模拟。"); return }
            session.checkConnection { [weak self] message in self?.show("定位连接检查", message) }
        case 3:
            show("安装与恢复指南", "首次：电脑签名安装 → 开启开发者模式 → 导入本设备配对文件 → 连接 Wi-Fi 和 LocalDevVPN。\n\n使用：选点 → 开始模拟 → 在地图 App 验证当前位置。\n\n结束：保持 VPN 连接 → 清除模拟定位 → 地图重新定位 → 再关闭 VPN。清除失败可重试；仍失败则关闭 VPN、重启设备，先验证真实位置。\n\n续签：在到期前手动刷新。每台设备分别签名和配对。")
        case 4:
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
            show("脱敏诊断", "App：\(version)\n系统：\(UIDevice.current.systemVersion)\n设备类型：\(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")\n操作进行中：\(session.busy ? "是" : "否")\n可能遗留模拟：\(session.needsClear ? "是" : "否")\n\n不包含账号、UDID、配对内容、IP 或位置收藏。")
        default:
            show("开源声明", "基于 SideStore 0.7.0-alpha 与 StikDebug 3.1.13，保留 AGPL-3.0 许可证及原作者声明。\n\nSideStore：github.com/SideStore/SideStore\nStikDebug：github.com/StikDebug/StikDebug\n\n对应源码与依赖说明随安装包提供，详见仓库 THIRD_PARTY_NOTICES.md。")
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
                guard let content = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
                _ = try PairingFileParser.parse(content: content)
                try PairingFileManager.shared.savePairingFile(contents: content)
                DispatchQueue.main.async {
                    self.importing = false
                    self.session.endMaintenance()
                    self.tableView.reloadData()
                    self.show("配对文件已保存", "请重新打开 App，让续签模块加载新配对文件。每台设备必须使用自己的文件；可再点击检查定位连接。")
                }
            } catch {
                DispatchQueue.main.async {
                    self.importing = false
                    self.session.endMaintenance()
                    self.tableView.reloadData()
                    self.show("导入失败", "文件无法读取或格式不正确。请用 iloader 为本设备重新生成配对文件。")
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
