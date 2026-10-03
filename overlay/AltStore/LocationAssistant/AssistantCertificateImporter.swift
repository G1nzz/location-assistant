import UIKit
import UniformTypeIdentifiers
import SideSign

@MainActor
final class AssistantCertificateImporter: NSObject, UIDocumentPickerDelegate {
    private weak var presenting: UIViewController?
    private let session = AssistantSession.shared
    private let queue = DispatchQueue(label: "locationassistant.certificate-import", qos: .userInitiated)
    private var pending = false

    init(presenting: UIViewController) { self.presenting = presenting }

    func start() {
        guard !pending, let presenting, session.beginMaintenance() else { return }
        pending = true
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: false)
        picker.delegate = self
        picker.shouldShowFileExtensions = true
        presenting.present(picker, animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish() }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let presenting else { finish(); return }
        guard ["p12", "pfx", "sideconf"].contains(url.pathExtension.lowercased()) else {
            finish(); show("文件类型不支持", AssistantCertificateError.invalidFile.localizedDescription); return
        }
        let alert = UIAlertController(title: "证书文件密码", message: "输入导出文件时设置的密码，无密码可留空。这不是 Apple 账号密码。文件只在本设备读取；账号备份只提取证书，不导入其中的账号密码。", preferredStyle: .alert)
        alert.addTextField { $0.isSecureTextEntry = true; $0.placeholder = "文件密码" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in self.finish() })
        alert.addAction(UIAlertAction(title: "导入", style: .default) { _ in
            let password = alert.textFields?.first?.text ?? ""
            self.read(url, password: password)
        })
        // Wait for the document picker to complete its dismissal before presenting.
        controller.dismiss(animated: true) { presenting.present(alert, animated: true) }
    }

    private func read(_ url: URL, password: String) {
        queue.async {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 2_000_000 else {
                    throw AssistantCertificateError.invalidFile
                }
                let data = try Data(contentsOf: url)
                let certificate: ALTCertificate
                if url.pathExtension.lowercased() == "sideconf" {
                    let backup = try ImportExport.decryptAccount(data, filePassword: password)
                    certificate = try CertificateManager.parse(backup.certificateData, password: backup.certificatePassword)
                } else {
                    certificate = try CertificateManager.parse(data, password: password.isEmpty ? nil : password)
                }
                guard !certificate.privateKey.isEmpty else { throw AssistantCertificateError.invalidFile }
                try CertificateManager.shared.setActiveCertificate(certificate)
                DispatchQueue.main.async {
                    self.finish()
                    self.show("续签证书已导入", "已保存到本设备钥匙串。请在续签页登录该证书所属的 Apple 签名账号；登录时还会核对证书是否有效。尚未完成自身续签。")
                }
            } catch {
                DispatchQueue.main.async {
                    self.finish()
                    self.show("导入失败", AssistantCertificateError.invalidFile.localizedDescription)
                }
            }
        }
    }

    private func finish() { pending = false; session.endMaintenance() }
    private func show(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        presenting?.present(alert, animated: true)
    }
}
