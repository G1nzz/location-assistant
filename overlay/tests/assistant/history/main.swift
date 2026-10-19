import Foundation

func expect(_ condition: Bool, _ message: String) {
    if !condition { print(message); exit(1) }
}

let name = "com.locationassistant.history-tests." + UUID().uuidString
let defaults = UserDefaults(suiteName: name)!
defer { defaults.removePersistentDomain(forName: name) }
let now = Date(timeIntervalSince1970: 1_790_000_000)
let expiry = now.addingTimeInterval(7 * 86_400)
var history = AssistantSigningHistory.load(from: defaults)
expect(history.event == nil && history.receipt == nil, "Fresh install has no invented auth or refresh receipt")
history.record(.certificateSaved, now: now, defaults: defaults)
history = .load(from: defaults)
expect(history.event?.kind == .certificateSaved && history.receipt == nil, "Certificate import is not authentication or renewal")
history.record(.accountVerified, now: now, defaults: defaults)
expect(AssistantSigningHistory.load(from: defaults).receipt == nil, "Apple login must not create a renewal receipt")
expect(history.summary.contains("不代表"), "Historical auth must not claim a live Apple session")
history.record(.refreshStarted, now: now, defaults: defaults)
history = .load(from: defaults)
expect(history.event?.kind == .refreshStarted && history.receipt == nil, "Process interruption must not appear as successful renewal")
expect(history.summary.contains("未收到完成回执"), "Interrupted renewal remains explicitly unconfirmed")
history.record(.refreshAccepted, now: now, defaults: defaults)
expect(history.event?.kind == .refreshUnconfirmed && history.receipt == nil, "Missing expiry must not produce a successful receipt")
history.record(.refreshAccepted, expiration: now.addingTimeInterval(-1), now: now, defaults: defaults)
expect(history.receipt == nil, "An expired profile cannot be treated as new renewal confirmation")
history.record(.refreshAccepted, expiration: expiry, now: now, defaults: defaults)
history = .load(from: defaults)
expect(history.receipt?.profileExpiration == expiry && history.receipt?.date == now, "Accepted expiry survives coordinator/process recreation")
history.record(.refreshFailed, message: "错误代码 -80045", now: now.addingTimeInterval(60), defaults: defaults)
history = .load(from: defaults)
expect(history.summary.contains("失败") && history.summary.contains("-80045"), "Failure remains visible after reopening")
expect(history.receipt?.date == now, "A failed retry must not advance the earlier success receipt")
history.record(.accountStarted, now: now, defaults: defaults)
expect(history.receipt?.profileExpiration == expiry, "Account revalidation must not rewrite the prior installed-profile receipt")
history.record(.accountFailed, message: String(repeating: "x", count: 10_000), now: now, defaults: defaults)
expect(history.event?.message?.count == 768, "Local diagnostic text is bounded")
let corrupt = Data("invalid record".utf8)
defaults.set(corrupt, forKey: AssistantSigningHistory.key)
expect(AssistantSigningHistory.load(from: defaults).receipt == nil, "Corrupt records never fabricate renewal success")
expect(defaults.data(forKey: AssistantSigningHistory.key) == corrupt, "Reading a corrupt history must not mutate it")
print("Signing history receipt persistence, interrupted refresh, expiry evidence and failure recovery tests passed")
