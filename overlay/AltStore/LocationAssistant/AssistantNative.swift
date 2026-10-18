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
static func preflight(ip: String) -> Int32 {
    guard AssistantIPv4.canonical(ip) == ip else { return 1 }
    guard let content = PairingFileManager.shared.fetchPairingFile() else { return 2 }
    do {
        let pairing = try AssistantPairingPolicy.normalize(Data(content.utf8),
            expectedUDID: Bundle.main.object(forInfoDictionaryKey: "ALTDeviceID") as? String)
        guard pairing.kind == .remote else { return 4 }
    } catch { return 2 }
    return 0
}

static func connect(ip: String) -> Int32 {
    if LocationSimulationState.locationSimulation != nil { return 0 }
    let check = preflight(ip: ip)
    guard check == 0 else { return check }
    guard let content = PairingFileManager.shared.fetchPairingFile() else { return 2 }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(49152).bigEndian

    let inetResult = ip.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
    guard inetResult == 1 else {
        return LocationSimulationStatus.invalidIP
    }

    var pairingHandle: OpaquePointer?
    let data = Data(content.utf8)
    let pairingError = data.withUnsafeBytes { bytes in
        rp_pairing_file_from_bytes(bytes.bindMemory(to: UInt8.self).baseAddress, UInt(data.count), &pairingHandle)
    }
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
    guard LocationSimulationState.adapter != nil, LocationSimulationState.handshake != nil else {
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.providerCreate
    }

    // The FFI may update remote pairing during tunnel establishment. Persist
    // successful updates so the next launch does not retry with obsolete keys.
    var pairingBytes: UnsafeMutablePointer<UInt8>?
    var pairingLength: UInt = 0
    if let error = rp_pairing_file_to_bytes(pairingHandle, &pairingBytes, &pairingLength) {
        idevice_error_free(error)
        LocationSimulationState.cleanup()
        return 5
    }
    guard let pairingBytes else { LocationSimulationState.cleanup(); return 5 }
    defer { idevice_data_free(pairingBytes, pairingLength) }
    guard pairingLength > 0, pairingLength <= 2_000_000 else { LocationSimulationState.cleanup(); return 5 }
    do {
        let updated = try AssistantPairingPolicy.normalize(Data(bytes: pairingBytes, count: Int(pairingLength)))
        let previous = try AssistantPairingPolicy.normalize(Data(content.utf8))
        if updated.content != previous.content {
            try PairingFileManager.shared.savePairingFile(contents: updated.content)
        }
    } catch { LocationSimulationState.cleanup(); return 5 }

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
    guard LocationSimulationState.remoteServer != nil else {
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

    // location_simulation_new borrows the remote server. Keep its owner alive
    // until cleanup frees the location client first and the server second.
    guard LocationSimulationState.locationSimulation != nil else {
        LocationSimulationState.cleanup()
        return LocationSimulationStatus.locationSimulation
    }
    return 0
}

static func set(ip: String, coordinate: CLLocationCoordinate2D) -> Int32 {
    guard AssistantCoordinate.valid(coordinate) else { return 11 }
    let connected = connect(ip: ip)
    guard connected == 0 else { return connected }
    guard let client = LocationSimulationState.locationSimulation else { return LocationSimulationStatus.locationSet }
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
    LocationSimulationState.cleanup()
    let code = connect(ip: ip)
    LocationSimulationState.cleanup()
    return code
}

static func disconnect() { LocationSimulationState.cleanup() }
}
