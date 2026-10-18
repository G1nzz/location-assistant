import Foundation
import CoreLocation
import idevice

func expect(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
let remote: [String: Any] = ["identifier": "host-one", "private_key": Data(repeating: 1, count: 32), "public_key": Data(repeating: 2, count: 32)]
let xml = String(data: try PropertyListSerialization.data(fromPropertyList: remote, format: .xml, options: 0), encoding: .utf8)!
let point = CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
func reset(_ failure: Int32) {
    AssistantNative.disconnect()
    expect(assistant_test_live_count() == 0, "Previous operation leaked native handles")
    assistant_test_reset(failure)
    PairingFileManager.shared.content = xml
    PairingFileManager.shared.failSave = false
    PairingFileManager.shared.saves = 0
}
func clean(_ message: String) {
    expect(assistant_test_live_count() == 0, message)
    expect(assistant_test_bad_free_order() == 0, "Borrowed remote server freed before its location client")
}
for (failure, expected) in [(Int32(1), Int32(2)), (2, 3), (3, 9), (4, 10), (5, 10), (6, 11), (8, 5), (10, 3), (11, 9)] {
    reset(failure)
    expect(AssistantNative.set(ip: "10.7.0.1", coordinate: point) == expected, "Fault must report the correct stage: \(failure)")
    clean("Failure path must release all handles: \(failure)")
}
reset(0)
expect(AssistantNative.preflight(ip: "10.7.0.1/32") == 1, "Invalid IP rejected before FFI")
PairingFileManager.shared.content = "invalid"
expect(AssistantNative.preflight(ip: "10.7.0.1") == 2, "Invalid pairing rejected before FFI")
clean("Preflight cannot allocate device handles")
reset(7)
expect(AssistantNative.set(ip: "10.7.0.1", coordinate: point) == 0, "Successful set")
expect(AssistantNative.clear(ip: "10.7.0.1") == 12, "Clear failure cannot be reported as success")
clean("Clear error releases resources")
reset(0)
for _ in 0..<100 {
    expect(AssistantNative.set(ip: "10.7.0.1", coordinate: point) == 0, "Repeated set")
    expect(AssistantNative.clear(ip: "10.7.0.1") == 0, "Repeated clear")
    clean("Repeated sessions must not accumulate native handles")
}
reset(9)
expect(AssistantNative.set(ip: "10.7.0.1", coordinate: point) == 0, "Updated remote pairing")
expect(PairingFileManager.shared.saves == 1, "Updated pairing must persist before sending position")
AssistantNative.disconnect(); clean("Updated pairing session cleanup")
reset(9)
PairingFileManager.shared.failSave = true
expect(AssistantNative.set(ip: "10.7.0.1", coordinate: point) == 5, "Unsaveable pairing must fail")
expect(assistant_test_set_calls() == 0, "Do not send a new position if updated pairing cannot persist")
clean("Pairing save failure cleanup")
print("Native fault injection, nil-client rejection, pairing persistence and 100-cycle resource lifetime tests passed")
