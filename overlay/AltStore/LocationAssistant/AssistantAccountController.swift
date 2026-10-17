import UIKit
import Combine

final class AssistantAccountController: UITableViewController {
    private let signing = AssistantSigningCoordinator.shared
    private let session = AssistantSession.shared
    private var observations = Set<AnyCancellable>()
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "续签"
        signing.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.tableView.reloadData() }
        }.store(in: &observations)
        session.$busy.sink { [weak self] _ in self?.tableView.reloadData() }.store(in: &observations)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        signing.reloadInstalledSignature()
        tableView.reloadData()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 2 : section == 1 ? 2 : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["当前安装包", "签名账号与证书", "续签状态"][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "到期时间直接读取当前安装包描述文件。免费签名通常约 7 天，建议提前刷新；过期后可能需要电脑覆盖安装。刷新前连接 Wi-Fi 和 LocalDevVPN，App 会先清除模拟并释放连接。" }
        if section == 1 { return "定位与签名验证分开运行。同一签名账号用于多台设备时，共享同一份含私钥证书；每台设备仍需自己的配对文件。不会自动撤销已有证书。" }
        return "认证服务连接成功只表示配置可读取，不代表 Apple 已允许登录，也不代表续签完成。"
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            cell.textLabel?.text = "当前签名到期时间"
            if let date = signing.expiration {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "zh_CN")
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                cell.detailTextLabel?.text = formatter.string(from: date)
                switch AssistantSignatureWindow.evaluate(expiration: date) {
                case .expired: cell.detailTextLabel?.textColor = .systemRed
                case .dueSoon: cell.detailTextLabel?.textColor = .systemOrange
                default: break
                }
            } else { cell.detailTextLabel?.text = signing.profileRead ? "无法读取安装包描述文件；不使用旧数据库时间代替" : "正在读取当前安装包…" }
            cell.selectionStyle = .none
        case (0, 1):
            cell.textLabel?.text = signing.working ? "续签操作进行中…" : "刷新自身签名"
            cell.textLabel?.textColor = session.busy ? .secondaryLabel : view.tintColor
        case (1, 0):
            cell.textLabel?.text = "登录或验证 Apple 签名账号"
            cell.textLabel?.textColor = session.busy ? .secondaryLabel : view.tintColor
        case (1, 1):
            cell.textLabel?.text = "本设备签名私钥"
            cell.detailTextLabel?.text = signing.hasPrivateKey ? "已保存；账号验证时还会核对证书有效性" : "尚未确认。已有证书的账号需先在设置中导入完整 .p12/.pfx 文件"
            cell.selectionStyle = .none
        default:
            cell.textLabel?.text = signing.status
            cell.selectionStyle = .none
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !session.busy, !signing.working else { return }
        if indexPath.section == 0 && indexPath.row == 1 { signing.refresh(presenting: self) }
        else if indexPath.section == 1 && indexPath.row == 0 {
            if session.needsClear {
                let alert = UIAlertController(title: "请先清除模拟定位", message: "定位状态尚未确认清除。请回到定位页清除，再验证签名账号。", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "知道了", style: .default))
                present(alert, animated: true)
            } else { signing.signIn(presenting: self) }
        }
    }
}
