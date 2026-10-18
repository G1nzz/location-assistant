// Local reliability patch for SideSign. AGPL-3.0, see THIRD_PARTY_NOTICES.md.
import Foundation

final class AnisetteSocketDeadline: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = true
    private var work: DispatchWorkItem?
    init(seconds: TimeInterval, queue: DispatchQueue = .global(qos: .utility), onTimeout: @escaping @Sendable () -> Void) {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let shouldFire = self.pending
            self.pending = false
            self.lock.unlock()
            if shouldFire { onTimeout() }
        }
        work = item
        queue.asyncAfter(deadline: .now() + seconds, execute: item)
    }
    func cancel() {
        lock.lock(); pending = false; lock.unlock()
        work?.cancel()
    }
    deinit { cancel() }
}
