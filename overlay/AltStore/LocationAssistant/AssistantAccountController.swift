import UIKit
import Combine

final class AssistantAccountController: UITableViewController {
    private let session = AssistantSession.shared
    private var observations = Set<AnyCancellable>()
    private var signingIn = false
    private var accountStatus = "签名账号由 SideStore 登录流程管理"

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "续签"
        session.$status.combineLatest(session.$busy).sink { [weak self] _, _ in self?.tableView.reloadData() }.store(in: &observations)
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); tableView.reloadData() }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 2 : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["自身签名", "签名账号", "当前状态"][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "刷新前连接 Wi-Fi 和 LocalDevVPN。免费签名通常约 7 天有效，建议提前手动刷新；过期后可能需要电脑重新安装。刷新会先清除模拟定位。" }
        if section == 1 { return accountStatus }
        return nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        if indexPath.section == 0 && indexPath.row == 0 {
            cell.textLabel?.text = "实际到期时间"
            if DatabaseManager.shared.isStarted, let app = InstalledApp.fetchAltStore(in: DatabaseManager.shared.viewContext) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "zh_CN")
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                cell.detailTextLabel?.text = formatter.string(from: app.expirationDate)
            } else { cell.detailTextLabel?.text = "尚未读取签名记录，请完成首次安装" }
            cell.selectionStyle = .none
        } else if indexPath.section == 0 {
            cell.textLabel?.text = "刷新自身签名"
            cell.textLabel?.textColor = session.busy || signingIn ? .secondaryLabel : view.tintColor
        } else if indexPath.section == 1 {
            cell.textLabel?.text = signingIn ? "正在登录…" : "登录或验证 Apple 签名账号"
            cell.textLabel?.textColor = session.busy || signingIn ? .secondaryLabel : view.tintColor
        } else {
            cell.textLabel?.text = session.status
            cell.selectionStyle = .none
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !session.busy, !signingIn else { return }
        if indexPath.section == 0 && indexPath.row == 1 {
            guard DatabaseManager.shared.isStarted else { return }
            session.refreshSelf(presenting: self)
        } else if indexPath.section == 1 {
            guard session.beginMaintenance() else {
                accountStatus = "请先清除模拟定位，再登录或验证签名账号"
                tableView.reloadData()
                return
            }
            signingIn = true
            tableView.reloadData()
            AppManager.shared.signIn(presentingViewController: self) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.signingIn = false
                    self.session.endMaintenance()
                    switch result {
                    case .success: self.accountStatus = "签名账号登录成功"
                    case .failure(let error): self.accountStatus = "登录未完成：\(AssistantSession.safeError(error))"
                    }
                    self.tableView.reloadData()
                }
            }
        }
    }
}
