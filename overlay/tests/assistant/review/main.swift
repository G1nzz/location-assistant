import Foundation

func expect(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}
func rejects(_ message: String, _ action: () throws -> Void) {
    do { try action(); fatalError(message) } catch {}
}

@main
struct ReviewTests {
    static func main() async throws {
        let remote: [String: Any] = ["identifier": "test-host", "private_key": Data(repeating: 1, count: 32), "public_key": Data(repeating: 2, count: 32)]
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            let data = try PropertyListSerialization.data(fromPropertyList: remote, format: format, options: 0)
            let snapshot = try AssistantPairingPolicy.normalize(data)
            expect(snapshot.kind == .remote, "XML and binary remote pairing are accepted")
            expect(snapshot.content.hasPrefix("<?xml"), "Normalize to a text format consumed by both backends")
        }
        var lockdown: [String: Any] = ["UDID": "000000000000ABCD", "SystemBUID": "test-buid", "HostID": "test-host", "WiFiMACAddress": "00:00:00:00:00:00"]
        for key in ["RootPrivateKey", "HostPrivateKey", "RootCertificate", "HostCertificate", "DeviceCertificate", "EscrowBag"] { lockdown[key] = Data([1]) }
        let legacy = try PropertyListSerialization.data(fromPropertyList: lockdown, format: .binary, options: 0)
        let parsed = try AssistantPairingPolicy.normalize(legacy, expectedUDID: "000000000000abcd")
        expect(parsed.kind == .lockdown, "Traditional pairing is identified, not mislabeled as remote")
        rejects("A different device must not replace current pairing") { _ = try AssistantPairingPolicy.normalize(legacy, expectedUDID: "000000000000FFFF") }
        rejects("Invalid plist must fail before saving") { _ = try AssistantPairingPolicy.normalize(Data("not a plist".utf8)) }
        var emptyKeys = remote; emptyKeys["private_key"] = Data()
        rejects("An empty private key is not usable pairing") {
            _ = try AssistantPairingPolicy.normalize(PropertyListSerialization.data(fromPropertyList: emptyKeys, format: .xml, options: 0))
        }
        expect(AssistantIPv4.canonical("010.7.0.1") == "10.7.0.1", "Saved addresses are accepted by inet_pton")
        for invalid in ["10.7.0.1/32", "10..0.1", "256.0.0.1", "10.7.0", "١.2.3.4", "-1.2.3.4"] {
            expect(AssistantIPv4.canonical(invalid) == nil, "Invalid IPv4 rejected: \(invalid)")
        }

        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/review-fixtures-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AssistantFavoriteStore(file: directory.appendingPathComponent("favorites.json"))
        expect(try store.load().isEmpty, "A missing collection starts empty")
        let point = AssistantFavorite(name: "中文收藏", latitude: 39.9, longitude: 116.4)
        try store.save([point])
        expect(try store.load().first?.name == point.name, "Favorite round trip")
        let corrupt = Data("{corrupt".utf8)
        try corrupt.write(to: store.file)
        rejects("Corrupt favorites must not appear as an empty writable collection") { _ = try store.load() }
        rejects("A failed load must prevent overwrite") { try store.save([point]) }
        expect(try Data(contentsOf: store.file) == corrupt, "Failed save preserves exact original bytes")
        let oversized = Data(repeating: 0, count: AssistantFavoriteStore.maximumBytes + 1)
        try oversized.write(to: store.file)
        rejects("Oversized collection is bounded") { _ = try store.load() }
        rejects("Oversized collection cannot be overwritten") { try store.save([point]) }
        expect(try Data(contentsOf: store.file).count == oversized.count, "Oversized original retained")

        let fired = DispatchSemaphore(value: 0)
        let deadline = AnisetteSocketDeadline(seconds: 0.01) { fired.signal() }
        expect(fired.wait(timeout: .now() + 3) == .success, "A stalled operation reaches its deadline")
        deadline.cancel()
        expect(fired.wait(timeout: .now()) == .timedOut, "Timeout action executes once")
        let queue = DispatchQueue(label: "review.timeout-queue")
        let blocker = DispatchSemaphore(value: 0), drained = DispatchSemaphore(value: 0), unexpected = DispatchSemaphore(value: 0)
        queue.async { blocker.wait() }
        let cancelled = AnisetteSocketDeadline(seconds: 0, queue: queue) { unexpected.signal() }
        cancelled.cancel()
        blocker.signal()
        queue.async { drained.signal() }
        expect(drained.wait(timeout: .now() + 3) == .success, "Queued timeout drained")
        expect(unexpected.wait(timeout: .now()) == .timedOut, "Finished operations are not cancelled by a queued timeout")

        await MainActor.run {
            for url in ["locationassistant://pairing?urlname=untrusted", "locationassistant://certificate?callback_template=untrusted", "locationassistant://install?url=https://example.invalid/a.ipa", "locationassistant://source?url=https://example.invalid", "file:///tmp/a.ipa"] {
                expect(!URLHandler.shared.handle(URL(string: url)!), "Legacy URL must never export pairing or certificates, or import an IPA")
            }
        }
        print("Pairing formats/device identity, favorite preservation, IPv4, socket deadlines and closed URL entrypoints tests passed")
    }
}
