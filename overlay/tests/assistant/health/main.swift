import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
let now = Date(timeIntervalSince1970: 1_800_000_000)
expect(AssistantSignatureWindow.evaluate(expiration: nil, now: now) == .unknown, "Missing installed profile cannot imply valid signing")
expect(AssistantSignatureWindow.evaluate(expiration: now, now: now) == .expired, "Expiry boundary is expired")
expect(AssistantSignatureWindow.evaluate(expiration: now.addingTimeInterval(86_400), now: now) == .dueSoon, "One day remaining needs refresh")
expect(AssistantSignatureWindow.evaluate(expiration: now.addingTimeInterval(7 * 86_400), now: now) == .valid, "Fresh seven day profile")
for code in [-80045, -22421, -90010, -45061] {
    let apple = NSError(domain: "Apple", code: code, userInfo: [NSLocalizedDescriptionKey: "private-account@example.invalid token=secret"])
    let inner = NSError(domain: "ConnectionWrapper", code: 0, userInfo: [NSUnderlyingErrorKey: apple])
    let outer = NSError(domain: "SideStore.OperationError", code: 21, userInfo: [NSUnderlyingErrorKey: inner])
    expect(AssistantFailureClassifier.authenticationCode(in: outer) == code, "Preserve nested authentication code, not generic operation 21")
}
expect(AssistantFailureClassifier.authenticationCode(in: NSError(domain: "Network", code: -1009)) == nil, "Network failure is not authentication rejection")
let ticket = AssistantCommandTicket()
let queue = DispatchQueue(label: "health-test")
let blocker = DispatchSemaphore(value: 0)
let completed = DispatchSemaphore(value: 0)
queue.async { blocker.wait() }
queue.async {
    expect(ticket.isCancelled, "A queued keepalive must observe cancellation before sending")
    completed.signal()
}
ticket.cancel()
blocker.signal()
expect(completed.wait(timeout: .now() + 2) == .success, "Queued keepalive test completed")
print("Installed signature, wrapped error classification and queued keepalive cancellation tests passed")
