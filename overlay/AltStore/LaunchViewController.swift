// Based on SideStore, AGPL-3.0. Location startup does not wait for signing,
// remote app sources, account imports, or JIT discovery.
import UIKit

final class LaunchViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        guard let destination = storyboard?.instantiateViewController(withIdentifier: "tabBarController") as? TabBarController else { return }
        addChild(destination)
        destination.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(destination.view)
        NSLayoutConstraint.activate([
            destination.view.topAnchor.constraint(equalTo: view.topAnchor),
            destination.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            destination.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            destination.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        destination.didMove(toParent: self)
    }
}
