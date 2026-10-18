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

let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/native-ddi")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for name in ["Image.dmg", "Image.dmg.trustcache", "BuildManifest.plist"] {
    try Data([1,2,3]).write(to: directory.appendingPathComponent(name))
}
for method in [AssistantDDIMethod.personalized, .cryptex] {
    reset(0)
    expect(AssistantNative.ddiStatus(ip: "10.7.0.1", method: method) == 0, "Mounted image")
    clean("Readiness inspection must release all handles")
    assistant_test_set_mounted(0)
    expect(AssistantNative.ddiStatus(ip: "10.7.0.1", method: method) == 20, "Missing image is distinct from unreachable")
    clean("Missing image inspection cleanup")
    expect(AssistantNative.mountDDI(ip: "10.7.0.1", method: method, directory: directory) == 0, "Mount with post-query")
    expect(assistant_test_mount_calls() == 1, "Mount once")
    clean("Mount cleanup")
    expect(AssistantNative.mountDDI(ip: "10.7.0.1", method: method, directory: directory) == 0, "Already mounted")
    expect(assistant_test_mount_calls() == 1, "Already mounted does not install again")
    clean("Already-mounted cleanup")
    reset(22); assistant_test_set_mounted(0)
    expect(AssistantNative.mountDDI(ip: "10.7.0.1", method: method, directory: directory) == 24, "Successful command without mounted status is failure")
    clean("Post-mount verification failure cleanup")
}
for (failure, code) in [(Int32(12), Int32(21)), (13,21), (14,21), (15,22), (16,21), (17,23), (18,23), (19,23), (20,23), (21,23)] {
    reset(failure); assistant_test_set_mounted(0)
    expect(AssistantNative.mountDDI(ip: "10.7.0.1", method: .personalized, directory: directory) == code, "Personalized fault \(failure)")
    expect(assistant_test_set_calls() == 0, "Preparation must not send coordinates")
    clean("Personalized fault cleanup \(failure)")
}
for (failure, code) in [(Int32(23), Int32(21)), (24,25), (25,25), (26,23)] {
    reset(failure); assistant_test_set_mounted(0)
    expect(AssistantNative.mountDDI(ip: "10.7.0.1", method: .cryptex, directory: directory) == code, "Cryptex fault \(failure)")
    expect(assistant_test_set_calls() == 0, "Cryptex preparation must not send coordinates")
    clean("Cryptex fault cleanup \(failure)")
}
reset(0); assistant_test_set_mounted(0)
expect(AssistantNative.set(ip: "10.7.0.1", coordinate: point) == 20, "Never submit if DDI missing")
expect(assistant_test_set_calls() == 0, "Missing DDI blocks position commands")
clean("No DDI set cleanup")
print("Personalized/Cryptex DDI readiness, mount, recheck and fault resource tests passed")
