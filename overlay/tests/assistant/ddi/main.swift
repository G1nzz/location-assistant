import Foundation
import CryptoKit

func expect(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
@main struct DDITests {
    static func main() async throws {
        for (major, minor, expected) in [(18,6,AssistantDDIMethod.personalized),(26,3,.personalized),(26,4,.cryptex),(26,6,.cryptex),(27,0,.cryptex)] {
            expect(AssistantDDIMethod.select(.init(majorVersion: major, minorVersion: minor, patchVersion: 0)) == expected, "Version dispatch")
        }
        let pinned = try JSONDecoder().decode(AssistantDDIManifest.self, from: Data(contentsOf: URL(fileURLWithPath: "AltStore/LocationAssistant/AssistantDDIManifest.json")))
        expect(try pinned.assets(for: .personalized).count == 3, "Pinned personalized set")
        expect(try pinned.assets(for: .cryptex).count == 5, "Pinned cryptex set")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/ddi-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data("verified DDI fixture".utf8)
        let hash = SHA256.hash(data: payload).map { String(format:"%02x", $0) }.joined()
        let commit = String(repeating: "a", count: 40)
        let files = ["Image.dmg", "BuildManifest.plist", "Image.dmg.trustcache"].map {
            AssistantDDIManifest.Asset(method: .personalized, name: $0,
                url: "https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/\(commit)/test/\($0)", size: payload.count, sha256: hash)
        }
        let manifest = AssistantDDIManifest(repository: "doronz88/DeveloperDiskImage", commit: commit, files: files)
        let good: AssistantDDIAssets.Download = { url, size in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let tmp = root.appendingPathComponent(UUID().uuidString)
            try payload.write(to: tmp)
            return (tmp, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let assets = AssistantDDIAssets(manifest: manifest, root: root.appendingPathComponent("cache"), download: good)
        let directory = try await assets.prepare(method: .personalized) { _ in }
        let cached = AssistantDDIAssets(manifest: manifest, root: assets.root) { _,_ in fatalError("Valid cache must not download") }
        _ = try await cached.prepare(method: .personalized) { _ in }
        try Data(repeating: 0, count: payload.count).write(to: directory.appendingPathComponent("Image.dmg"))
        _ = try await assets.prepare(method: .personalized) { _ in }
        expect(try AssistantDDIAssets.verify(directory.appendingPathComponent("Image.dmg"), asset: files[0]), "Same-size corruption is redownloaded")
        for status in [200,502] {
            let bad = AssistantDDIAssets(manifest: manifest, root: root.appendingPathComponent("bad-\(status)")) { url,_ in
                let tmp = root.appendingPathComponent(UUID().uuidString)
                try Data(repeating: 0, count: payload.count).write(to: tmp)
                return (tmp, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            do { _ = try await bad.prepare(method: .personalized) { _ in }; fatalError("Bad transfer accepted") }
            catch is AssistantDDIError {}
            expect(!FileManager.default.fileExists(atPath: bad.root.appendingPathComponent(commit+"/personalized/Image.dmg").path), "Never publish bad data")
        }
        let cancelled = AssistantDDIAssets(manifest: manifest, root: root.appendingPathComponent("cancelled")) { _,_ in throw CancellationError() }
        do { _ = try await cancelled.prepare(method: .personalized) { _ in }; fatalError("Cancellation swallowed") }
        catch is CancellationError {}
        let delayed = AssistantDDIAssets(manifest: manifest, root: root.appendingPathComponent("task-cancelled")) { url,_ in
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return try await good(url, payload.count)
        }
        let task = Task { try await delayed.prepare(method: .personalized) { _ in } }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        do { _ = try await task.value; fatalError("Task cancellation swallowed") }
        catch is CancellationError {}
        // Verify the exact pinned public assets too when provided by CI.
        if let path = ProcessInfo.processInfo.environment["ASSISTANT_DDI_FIXTURES"] {
            for file in pinned.files {
                expect(try AssistantDDIAssets.verify(URL(fileURLWithPath: path).appendingPathComponent(file.method.rawValue+"/"+file.name), asset: file), "Pinned real asset digest")
            }
        }
        // Exercise the real URLSession path against a loopback fixture, with no
        // Apple account or external network dependency. Check file ownership
        // after the session is invalidated, and prove redirects are not followed.
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-u", "-c", """
        from http.server import HTTPServer, BaseHTTPRequestHandler
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == '/redirect':
                    self.send_response(302)
                    self.send_header('Location', '/unexpected')
                    self.end_headers()
                else:
                    self.send_response(200)
                    self.send_header('Content-Length', '7')
                    self.end_headers()
                    self.wfile.write(b'ddi-ok!')
            def log_message(self, *args): pass
        server = HTTPServer(('127.0.0.1', 0), Handler)
        print(server.server_port, flush=True)
        server.serve_forever()
        """]
        let pipe = Pipe()
        server.standardOutput = pipe
        try server.run()
        defer { server.terminate(); server.waitUntilExit() }
        var line = Data()
        while let byte = try pipe.fileHandleForReading.read(upToCount: 1), !byte.isEmpty {
            if byte == Data([10]) { break }; line.append(byte)
        }
        let port = Int(String(decoding: line, as: UTF8.self))!
        let (downloaded, response) = try await AssistantDDIAssets.downloadAsset(URL(string: "http://127.0.0.1:\(port)/ok")!, 7)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        expect((response as? HTTPURLResponse)?.statusCode == 200, "Real URLSession response")
        expect(try Data(contentsOf: downloaded) == Data("ddi-ok!".utf8), "Downloaded file survives session invalidation")
        let (redirected, redirectResponse) = try await AssistantDDIAssets.downloadAsset(URL(string: "http://127.0.0.1:\(port)/redirect")!, 100)
        defer { try? FileManager.default.removeItem(at: redirected) }
        expect((redirectResponse as? HTTPURLResponse)?.statusCode == 302, "Redirect must not be followed")
        print("DDI version dispatch, pinned manifests, disk cache, integrity, HTTP failure and cancellation tests passed")
        print("Real URLSession disk-download lifetime and redirect refusal tests passed")
    }
}
