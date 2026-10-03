import UIKit
import MapKit
import Combine

final class AssistantLocationController: UIViewController, MKMapViewDelegate, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate {
    private let session = AssistantSession.shared
    private let map = MKMapView()
    private let search = UISearchBar()
    private let results = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private let selectedLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private var coordinate: CLLocationCoordinate2D?
    private var selectedName = "地图选点"
    private var annotation: MKPointAnnotation?
    private var searchItems: [MKMapItem] = []
    private var debounce: DispatchWorkItem?
    private var activeSearch: MKLocalSearch?
    private var searchGeneration = 0
    private var observations = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "定位"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "收藏", style: .plain, target: self, action: #selector(showFavorites)),
            UIBarButtonItem(title: "坐标", style: .plain, target: self, action: #selector(enterCoordinate))
        ]
        search.placeholder = "搜索地点（停顿后搜索）"
        search.delegate = self
        map.delegate = self
        map.showsUserLocation = false
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pickPoint(_:))))
        results.dataSource = self
        results.delegate = self
        results.isHidden = true
        results.keyboardDismissMode = .onDrag
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.numberOfLines = 0
        selectedLabel.font = .preferredFont(forTextStyle: .footnote)
        selectedLabel.numberOfLines = 0
        selectedLabel.text = "点击地图选点，或输入 WGS-84 经纬度"
        startButton.setTitle("开始模拟", for: .normal)
        startButton.addTarget(self, action: #selector(start), for: .touchUpInside)
        clearButton.setTitle("清除模拟定位", for: .normal)
        clearButton.addTarget(self, action: #selector(clear), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [startButton, clearButton])
        buttons.distribution = .fillEqually
        let footer = UIStackView(arrangedSubviews: [selectedLabel, statusLabel, buttons])
        footer.axis = .vertical
        footer.spacing = 8
        for item in [search, map, results, footer] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: safe.topAnchor),
            search.leadingAnchor.constraint(equalTo: safe.leadingAnchor), search.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16), footer.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            buttons.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            map.topAnchor.constraint(equalTo: search.bottomAnchor), map.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            map.leadingAnchor.constraint(equalTo: safe.leadingAnchor), map.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            results.topAnchor.constraint(equalTo: map.topAnchor), results.bottomAnchor.constraint(equalTo: map.bottomAnchor),
            results.leadingAnchor.constraint(equalTo: map.leadingAnchor), results.trailingAnchor.constraint(equalTo: map.trailingAnchor)
        ])
        session.$status.combineLatest(session.$busy).sink { [weak self] status, busy in
            self?.statusLabel.text = status
            self?.startButton.isEnabled = !busy && self?.coordinate != nil
            self?.clearButton.isEnabled = !busy
            self?.navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = !busy }
        }.store(in: &observations)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        invalidateSearch()
        search.resignFirstResponder()
    }

    private func invalidateSearch() {
        searchGeneration += 1
        debounce?.cancel()
        debounce = nil
        activeSearch?.cancel()
        activeSearch = nil
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        invalidateSearch()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { searchItems = []; results.reloadData(); results.isHidden = true; return }
        let generation = searchGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = self.map.region
            let operation = MKLocalSearch(request: request)
            self.activeSearch = operation
            operation.start { [weak self] response, error in
                DispatchQueue.main.async {
                    guard let self, self.searchGeneration == generation else { return }
                    self.searchItems = Array((response?.mapItems ?? []).prefix(20))
                    self.results.reloadData()
                    self.results.isHidden = self.searchItems.isEmpty
                    if error != nil { self.selectedLabel.text = "搜索失败，请检查网络；仍可地图选点或输入坐标" }
                    else if self.searchItems.isEmpty { self.selectedLabel.text = "未找到地点，请换关键词" }
                }
            }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { searchItems.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "result") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "result")
        let item = searchItems[indexPath.row]
        cell.textLabel?.text = item.name
        cell.detailTextLabel?.text = item.placemark.title
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = searchItems[indexPath.row]
        invalidateSearch()
        select(AssistantCoordinate.mapToWGS84(item.placemark.coordinate), name: item.name ?? "搜索地点", recenter: true)
        results.isHidden = true
        search.resignFirstResponder()
    }

    @objc private func pickPoint(_ gesture: UITapGestureRecognizer) {
        guard !session.busy else { return }
        search.resignFirstResponder()
        invalidateSearch()
        results.isHidden = true
        let mapCoordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
        select(AssistantCoordinate.mapToWGS84(mapCoordinate), name: "地图选点", recenter: false)
    }

    private func select(_ value: CLLocationCoordinate2D, name: String, recenter: Bool) {
        guard AssistantCoordinate.valid(value) else { return }
        coordinate = value
        selectedName = name
        selectedLabel.text = String(format: "%@ · WGS-84：%.6f, %.6f", name, value.latitude, value.longitude)
        if let annotation { map.removeAnnotation(annotation) }
        let pin = MKPointAnnotation()
        pin.coordinate = AssistantCoordinate.wgs84ToMap(value)
        pin.title = name
        annotation = pin
        map.addAnnotation(pin)
        if recenter { map.setRegion(MKCoordinateRegion(center: pin.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500), animated: false) }
        startButton.isEnabled = !session.busy
    }

    @objc private func start() { if let coordinate { session.start(coordinate) } }
    @objc private func clear() { session.clear() }

    @objc private func enterCoordinate() {
        let alert = UIAlertController(title: "输入 WGS-84 坐标", message: "纬度在前，经度在后。此入口不执行 GCJ-02 转换。", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "纬度，例如 39.9087"; $0.keyboardType = .numbersAndPunctuation }
        alert.addTextField { $0.placeholder = "经度，例如 116.3975"; $0.keyboardType = .numbersAndPunctuation }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "选择", style: .default) { [weak self] _ in
            guard let value = AssistantCoordinate.parse(latitude: alert.textFields?[0].text ?? "", longitude: alert.textFields?[1].text ?? "") else {
                self?.selectedLabel.text = "坐标无效：纬度 -90～90，经度 -180～180"
                return
            }
            self?.select(value, name: "输入坐标", recenter: true)
        })
        present(alert, animated: true)
    }

    @objc private func showFavorites() {
        let controller = AssistantFavoritesController(selected: coordinate, selectedName: selectedName) { [weak self] point in
            self?.select(point.coordinate, name: point.name, recenter: true)
        }
        navigationController?.pushViewController(controller, animated: true)
    }
}
