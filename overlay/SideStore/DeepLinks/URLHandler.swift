// The assistant does not expose upstream import/export callback URLs.
// In particular, a web page must never trigger pairing/private-key export.
import Foundation

@MainActor
final class URLHandler {
    static let shared = URLHandler()
    private init() {}
    @discardableResult
    func handle(_ url: URL) -> Bool { false }
}
