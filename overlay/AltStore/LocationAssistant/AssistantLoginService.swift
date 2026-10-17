import Foundation
import SideSign
import AnisetteKit

actor AssistantLoginService {
    static let shared = AssistantLoginService()
    private struct State: Codable { let identifier: UUID; var blob: Data? }
    private var clients: [String: (Date, AssistantLoginPolicy.Client)] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private func stateKey(_ server: URL) -> String { "assistant.anisette.v1." + (server.host ?? "invalid") }

    private func loadState(_ server: URL) throws -> State {
        if let data = try AssistantLocalKeychain.read(stateKey(server)) {
            return try JSONDecoder().decode(State.self, from: data)
        }
        let state = State(identifier: UUID(), blob: nil)
        try AssistantLocalKeychain.write(JSONEncoder().encode(state), key: stateKey(server))
        return state
    }

    private func client(_ server: URL) async throws -> AssistantLoginPolicy.Client {
        if let cached = clients[server.absoluteString], Date().timeIntervalSince(cached.0) < 300 { return cached.1 }
        var request = URLRequest(url: server.appendingPathComponent("v3/client_info"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw AssistantLoginError.serviceUnavailable }
        let result = try AssistantLoginPolicy.decodeClient(data)
        clients[server.absoluteString] = (Date(), result)
        return result
    }

    func clearMemoryCache() {
        clients.removeAll()
        SideSign.AnisetteDataManager.shared.clearCache()
    }

    func fetch() async throws -> ALTAnisetteData {
        for address in AssistantLoginPolicy.serviceURLs {
            guard let server = URL(string: address) else { continue }
            do {
                let configuration = try await client(server)
                var state = try loadState(server)
                var headers = AnisetteRequestHeaders()
                headers.clientInfo = configuration.clientInfo
                headers.userAgent = configuration.userAgent
                let result = try await SideSign.AnisetteDataManager.shared.fetchAnisetteData(
                    mode: .remote(server: server), identifier: state.identifier,
                    existingAdiBlob: state.blob, headers: headers)
                if let blob = result.newAdiBlob {
                    state.blob = blob
                    try AssistantLocalKeychain.write(JSONEncoder().encode(state), key: stateKey(server))
                }
                return result.data
            } catch let error as AssistantLoginError {
                if case .storage = error { throw error }
            } catch is CancellationError { throw CancellationError() }
            catch { /* Try only the next fixed service; never log auth payloads. */ }
        }
        throw AssistantLoginError.serviceUnavailable
    }

    func resetCache() throws {
        clearMemoryCache()
        for address in AssistantLoginPolicy.serviceURLs {
            if let server = URL(string: address) { try AssistantLocalKeychain.write(nil, key: stateKey(server)) }
        }
    }

    func checkService() async throws {
        clients.removeAll()
        for address in AssistantLoginPolicy.serviceURLs {
            if let url = URL(string: address), (try? await client(url)) != nil { return }
        }
        throw AssistantLoginError.serviceUnavailable
    }
}
