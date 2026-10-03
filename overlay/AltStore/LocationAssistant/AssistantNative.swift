// Adapted from StikDebug 3.1.13, AGPL-3.0. See THIRD_PARTY_NOTICES.md.
// All entrypoints must run on AssistantSession's serial work queue.
import Foundation
import CoreLocation
import idevice

private enum LocationSimulationStatus {
    static let ok: Int32 = 0
    static let invalidIP: Int32 = 1
    static let pairingRead: Int32 = 2
    static let providerCreate: Int32 = 3
    static let remoteServer: Int32 = 9
    static let locationSimulation: Int32 = 10
    static let locationSet: Int32 = 11
    static let locationClear: Int32 = 12
}

private enum LocationSimulationState {
    static var adapter: OpaquePointer?
    static var handshake: OpaquePointer?
    static var remoteServer: OpaquePointer?
    static var locationSimulation: OpaquePointer?

    static func cleanup() {
        if let locationSimulation {
            location_simulation_free(locationSimulation)
            self.locationSimulation = nil
        }
        if let remoteServer {
            remote_server_free(remoteServer)
            self.remoteServer = nil
        }
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
    }
}

enum AssistantNative {
static func connect(ip: String) -> Int32 {
    if LocationSimulationState.locationSimulation != nil { return 0 }

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
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(49152).bigEndian

    let inetResult = ip.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
    guard inetResult == 1 else {
        return LocationSimulationStatus.invalidIP
    }

    var pairingHandle: OpaquePointer?
    let pairingError = pairingPath.withCString { rp_pairing_file_read($0, &pairingHandle) }
    if let pairingError {
        idevice_error_free(pairingError)
        return LocationSimulationStatus.pairingRead
    }

    guard let pairingHandle else {
        return LocationSimulationStatus.pairingRead
    }

    defer { rp_pairing_file_free(pairingHandle) }

    let providerError = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            tunnel_create_rppairing(
                $0,
                socklen_t(MemoryLayout<sockaddr_in>.stride),
                "StikDebugLocation",
                pairingHandle,
                nil,
                nil,
                &LocationSimulationState.adapter,
                &LocationSimulationState.handshake
            )
        }
    }

    if let providerError {
        idevice_error_free(providerError)
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.providerCreate
    }

    let remoteServerError = remote_server_connect_rsd(
        LocationSimulationState.adapter,
        LocationSimulationState.handshake,
        &LocationSimulationState.remoteServer
    )
    if let remoteServerError {
        idevice_error_free(remoteServerError)
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.remoteServer
    }

    let locationSimulationError = location_simulation_new(
        LocationSimulationState.remoteServer,
        &LocationSimulationState.locationSimulation
    )
    if let locationSimulationError {
        idevice_error_free(locationSimulationError)
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.locationSimulation
    }

    LocationSimulationState.remoteServer = nil

    return 0
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

static func clear(ip: String) -> Int32 {
    let code = connect(ip: ip)
    guard code == 0 else { return code }
    guard let locationSimulation = LocationSimulationState.locationSimulation else {
        return LocationSimulationStatus.locationClear
    }

    let ffiError = location_simulation_clear(locationSimulation)
    LocationSimulationState.cleanup()

    if let ffiError {
        idevice_error_free(ffiError)
        return LocationSimulationStatus.locationClear
    }

    return LocationSimulationStatus.ok
}

static func check(ip: String) -> Int32 {
    let alreadyConnected = LocationSimulationState.locationSimulation != nil
    let code = connect(ip: ip)
    if !alreadyConnected { LocationSimulationState.cleanup() }
    return code
}

static func disconnect() { LocationSimulationState.cleanup() }
}
