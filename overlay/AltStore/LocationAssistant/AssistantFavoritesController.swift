import UIKit
import CoreLocation

struct AssistantFavorite: Codable {
    let name: String
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

final class AssistantFavoritesController: UITableViewController {
    private let selected: CLLocationCoordinate2D?
    private let selectedName: String
    private let onSelect: (AssistantFavorite) -> Void
    private var items: [AssistantFavorite] = []
    private var saving = false
    private static let queue = DispatchQueue(label: "locationassistant.favorites", qos: .utility)
    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AssistantFavorites.json")
    }
    init(selected: CLLocationCoordinate2D?, selectedName: String, onSelect: @escaping (AssistantFavorite) -> Void) {
        self.selected = selected
        self.selectedName = selectedName
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "位置收藏"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "收藏当前点", style: .plain, target: self, action: #selector(add))
        navigationItem.rightBarButtonItem?.isEnabled = false
        Self.queue.async {
            let items = (try? JSONDecoder().decode([AssistantFavorite].self, from: Data(contentsOf: Self.file))) ?? []
            DispatchQueue.main.async {
                self.items = items.filter { AssistantCoordinate.valid($0.coordinate) }
                self.navigationItem.rightBarButtonItem?.isEnabled = self.selected != nil
                self.tableView.reloadData()
            }
        }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "favorite") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "favorite")
        let item = items[indexPath.row]
        cell.textLabel?.text = item.name
        cell.detailTextLabel?.text = String(format: "%.6f, %.6f", item.latitude, item.longitude)
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect(items[indexPath.row])
        navigationController?.popViewController(animated: true)
    }
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { !saving }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, !saving else { return }
        var updated = items
        updated.remove(at: indexPath.row)
        save(updated)
    }
    @objc private func add() {
        guard !saving, let selected else { return }
        let alert = UIAlertController(title: "收藏位置", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = self.selectedName }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let name = String((alert.textFields?.first?.text ?? "收藏位置").prefix(100))
            self.save(self.items + [AssistantFavorite(name: name, latitude: selected.latitude, longitude: selected.longitude)])
        })
        present(alert, animated: true)
    }
    private func save(_ updated: [AssistantFavorite]) {
        saving = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        Self.queue.async {
            do {
                let file = Self.file
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(updated).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                DispatchQueue.main.async { self.items = updated; self.finishedSaving(); self.tableView.reloadData() }
            } catch {
                DispatchQueue.main.async {
                    self.finishedSaving()
                    let alert = UIAlertController(title: "保存失败", message: "请检查设备剩余空间后重试。原收藏未修改。", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "知道了", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }
    private func finishedSaving() { saving = false; navigationItem.rightBarButtonItem?.isEnabled = selected != nil }
}
