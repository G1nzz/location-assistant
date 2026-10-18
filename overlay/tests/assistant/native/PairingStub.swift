import Foundation

final class PairingFileManager {
    static let shared = PairingFileManager()
    var content: String?
    var saves = 0
    var failSave = false
    func fetchPairingFile() -> String? { content }
    func savePairingFile(contents: String) throws {
        if failSave { throw CocoaError(.fileWriteOutOfSpace) }
        content = contents
        saves += 1
    }
}
