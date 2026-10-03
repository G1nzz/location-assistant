"""Reproducibly vendor the minimal StikDebug FFI adapter into the SideStore fork."""
import hashlib
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
STIK_COMMIT = "4bdfc92aa7cebd7a534f1e1ef56415f5727402de"

def integrate(source: Path):
    original = (source / "StikDebug/Device/IdeviceFFIBridge.swift").read_text(encoding="utf-8")
    native = original[original.index("private enum LocationSimulationStatus {"):]
    start = native.index("func simulate_location(")
    connect_start = native.index("    var address = sockaddr_in()", start)
    connect_end = native.index("    let locationSetError = location_simulation_set(", connect_start)
    connection = native[connect_start:connect_end]
    clear_start = native.index("func clear_simulated_location()")
    clear = native[clear_start:].replace("func clear_simulated_location() -> Int32 {", "static func clear(ip: String) -> Int32 {\n    let code = connect(ip: ip)\n    guard code == 0 else { return code }")
    state_end = native.index("enum LocationSimulationCommandQueue")
    declarations = native[:state_end]
    connection = connection.replace("deviceIP", "ip").replace("pairingFile.withCString", "pairingPath.withCString")
    # SideStore's pairing manager is the single source of truth. Never embed a real pairing.
    pairing = '''
    guard let content = PairingFileManager.shared.fetchPairingFile() else { return 2 }
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AssistantPairing", isDirectory: true)
    let file = directory.appendingPathComponent("pairing.plist")
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var protected = file
        if (try? String(contentsOf: file, encoding: .utf8)) != content {
            try content.write(to: file, atomically: true, encoding: .utf8)
        }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                                               .posixPermissions: 0o600], ofItemAtPath: file.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
    } catch { return 2 }
    let pairingPath = file.path
'''
    body = '''// Adapted from StikDebug 3.1.13, AGPL-3.0. See THIRD_PARTY_NOTICES.md.
// All entrypoints must run on AssistantSession's serial work queue.
import Foundation
import CoreLocation
import idevice

''' + declarations + '''enum AssistantNative {
static func connect(ip: String) -> Int32 {
    if LocationSimulationState.locationSimulation != nil { return 0 }
''' + pairing + connection + '''    return 0
}

static func set(ip: String, coordinate: CLLocationCoordinate2D) -> Int32 {
    guard AssistantCoordinate.valid(coordinate) else { return 11 }
    let connected = connect(ip: ip)
    guard connected == 0, let client = LocationSimulationState.locationSimulation else { return connected }
    if let error = location_simulation_set(client, coordinate.latitude, coordinate.longitude) {
        idevice_error_free(error)
        LocationSimulationState.cleanup()
        return 11
    }
    return 0
}

''' + clear + '''
static func check(ip: String) -> Int32 {
    let alreadyConnected = LocationSimulationState.locationSimulation != nil
    let code = connect(ip: ip)
    if !alreadyConnected { LocationSimulationState.cleanup() }
    return code
}

static func disconnect() { LocationSimulationState.cleanup() }
}
'''
    (ROOT / "AltStore/LocationAssistant/AssistantNative.swift").write_text(body, encoding="utf-8")
    vendor = ROOT / "Vendor/idevice"
    vendor.mkdir(parents=True, exist_ok=True)
    for name in ["idevice.h", "module.modulemap", "libidevice_ffi.a"]:
        shutil.copy2(source / "StikDebug/idevice" / name, vendor / name)
    shutil.copy2(source / "LICENSE", ROOT / "Vendor/StikDebug-LICENSE")
    lock = json.loads((ROOT / "upstream-lock.json").read_text(encoding="utf-8"))
    lock["stikdebug"]["ffi_sha256"] = hashlib.sha256((vendor / "libidevice_ffi.a").read_bytes()).hexdigest()
    (ROOT / "upstream-lock.json").write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__":
    integrate(Path(sys.argv[1]).resolve())
