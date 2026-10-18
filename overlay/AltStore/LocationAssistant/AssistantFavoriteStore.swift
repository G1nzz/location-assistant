import Foundation

struct AssistantFavorite: Codable {
    let name: String
    let latitude: Double
    let longitude: Double
}


struct AssistantFavoriteStore {
    let file: URL
    static let maximumBytes = 2_000_000
    func load() throws -> [AssistantFavorite] {
        let data: Data
        do { data = try Data(contentsOf: file, options: .mappedIfSafe) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        guard data.count <= Self.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        let items = try JSONDecoder().decode([AssistantFavorite].self, from: data)
        guard items.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return items
    }
    func save(_ items: [AssistantFavorite]) throws {
        // Refuse to overwrite an unreadable/corrupt existing collection.
        _ = try load()
        let data = try JSONEncoder().encode(items)
        guard data.count <= Self.maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
    }
}
