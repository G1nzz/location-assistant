import Foundation

enum AssistantIPv4 {
    static func canonical(_ value: String) -> String? {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var numbers = [String]()
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(part), (0...255).contains(number) else { return nil }
            numbers.append(String(number))
        }
        return numbers.joined(separator: ".")
    }
}

enum AssistantSignatureWindow: Equatable {
    case unknown, expired, dueSoon, valid
    static func evaluate(expiration: Date?, now: Date = Date()) -> Self {
        guard let expiration else { return .unknown }
        let remaining = expiration.timeIntervalSince(now)
        if remaining <= 0 { return .expired }
        if remaining <= 2 * 86_400 { return .dueSoon }
        return .valid
    }
}

// A cancelled dispatch source may already have a handler queued.
final class AssistantCommandTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true }
}

enum AssistantFailureClassifier {
    static let authenticationCodes: Set<Int> = [-80045, -90010, -22421, -22411, -22406, -45061]
    // Return only known numeric codes, never arbitrary server text or userInfo.
    static func authenticationCode(in error: NSError) -> Int? {
        var pending = [error]
        var visited = Set<ObjectIdentifier>()
        while let current = pending.popLast(), visited.count < 16 {
            guard visited.insert(ObjectIdentifier(current)).inserted else { continue }
            if authenticationCodes.contains(current.code) { return current.code }
            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError { pending.append(underlying) }
            if let multiple = current.userInfo["NSMultipleUnderlyingErrorsKey"] as? [NSError] { pending.append(contentsOf: multiple.prefix(16)) }
        }
        return nil
    }
}
