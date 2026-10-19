"""Exercise the real lazy signing-bootstrap body against destructive legacy upkeep.

The baseline inserts the removed production call and must reproduce loss of an
already imported key. The fixed body must retain key/account/pairing/favorites
on first login, repeated calls, database failure/retry, and process recreation.
Only dependencies are stubs; the coordinator body and legacy manager are read
from the materialized production sources, never copied into the fixture.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def method(source, name):
    start = source.index(name)
    opening = source.index('{', start)
    cursor, depth = opening + 1, 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor].replace('private func', 'func', 1)


STUBS = r'''
import Foundation

enum Fixture { static var group: URL?; static var databaseFails = false; static var reconciliations = 0 }
enum ExpectedFailure: Error { case database }
final class Keychain {
    static let shared = Keychain()
    var certificate = Data([1, 2, 3]), account = Data([4]), pairing = Data([5]), favorites = Data([6])
    func clearAll() { certificate = Data(); account = Data() }
}
final class DatabaseManager {
    static let shared = DatabaseManager()
    func start() async throws { if Fixture.databaseFails { throw ExpectedFailure.database } }
}
final class AuthManager {
    static let shared = AuthManager()
    func signOut(keepCertificate: Bool, keepAnisetteData: Bool) {
        Keychain.shared.account = Data()
        if !keepCertificate { Keychain.shared.certificate = Data() }
    }
}
final class AnisetteDataManager { static let shared = AnisetteDataManager(); func clearCache() {} }
enum AppDelegate { static func reconcileSelfReinstallationIfNeeded() { Fixture.reconciliations += 1 } }
extension FileManager { var altstoreSharedDirectory: URL? { Fixture.group } }
extension UserDefaults { var tunnelOverridePeerIp: String? { get { nil } set {} } }
func debugLog(_ text: String) {}
func verify(_ value: Bool, _ message: String) {
    if !value { print(message); exit(42) }
}
'''

MAIN = r'''
@main struct SigningBootstrapTests {
    static func main() async throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let key = Keychain.shared
        for counter in [0, 1, 2, 3] {
            let group = base.appendingPathComponent("group-\(counter)", isDirectory: true)
            try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
            Fixture.group = group
            if counter > 0 { try "\(counter)".write(to: group.appendingPathComponent(".maintenance_counter"), atomically: true, encoding: .utf8) }
            Fixture.reconciliations = 0
            Fixture.databaseFails = false
            key.certificate = Data([1, 2, 3]); key.account = Data([4]); key.pairing = Data([5]); key.favorites = Data([6])
            let owner = BootstrapOwner()
            try await owner.prepareDatabase()
            verify(key.certificate == Data([1, 2, 3]), "Imported private key was deleted during first signing bootstrap")
            verify(key.account == Data([4]), "Saved credentials must survive lazy database startup")
            try await owner.prepareDatabase()
            verify(Fixture.reconciliations == 1, "Reconciliation must not repeat within one signing session")
            try await BootstrapOwner().prepareDatabase()
            verify(key.certificate == Data([1, 2, 3]) && key.account == Data([4]), "A new coordinator must retain imported credentials")
            verify(key.pairing == Data([5]) && key.favorites == Data([6]), "Bootstrap must preserve pairing and favorites")
        }
        Fixture.group = nil
        Fixture.databaseFails = true
        let retry = BootstrapOwner()
        do { try await retry.prepareDatabase(); verify(false, "Database error was hidden") } catch ExpectedFailure.database {}
        verify(!retry.databasePrepared, "Failed initialization must remain retryable")
        verify(key.certificate == Data([1, 2, 3]) && key.account == Data([4]), "Failed database initialization must not erase credentials")
        Fixture.databaseFails = false
        try await retry.prepareDatabase()
        verify(retry.databasePrepared && key.certificate == Data([1, 2, 3]), "Retry must preserve credentials without an app-group counter")
    }
}
'''


def main():
    coordinator = (ROOT / 'AltStore/LocationAssistant/AssistantSigningCoordinator.swift').read_text(encoding='utf-8')
    bootstrap = method(coordinator, 'private func prepareDatabase()')
    assert 'MaintenanceManager' not in bootstrap, 'Destructive legacy maintenance reintroduced'
    legacy = (ROOT / 'SideStore/MaintenanceManager.swift').read_text(encoding='utf-8').replace('import SideSign', '')
    assert 'Keychain.shared.clearAll()' in legacy, 'Baseline no longer represents the pinned upstream'
    baseline = bootstrap.replace('AppDelegate.reconcileSelfReinstallationIfNeeded()',
                                 'AppDelegate.reconcileSelfReinstallationIfNeeded()\n                MaintenanceManager.shared.performMaintenanceIfNeeded()')
    build = ROOT / '.build'
    build.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='signing-lifecycle-', dir=build) as temporary:
        directory = Path(temporary)
        for name, implementation, expected in [('legacy', baseline, 42), ('fixed', bootstrap, 0)]:
            source = directory / (name + '.swift')
            owner = 'final class BootstrapOwner { var databasePrepared = false\n' + implementation + '\n}\n'
            source.write_text(STUBS + legacy + owner + MAIN, encoding='utf-8')
            executable = directory / name
            subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source), '-o', str(executable)], check=True)
            fixture = directory / (name + '-data')
            result = subprocess.run([str(executable), str(fixture)], capture_output=True, text=True)
            if result.returncode != expected:
                raise RuntimeError(f'{name} bootstrap returned {result.returncode}, expected {expected}: {result.stdout}{result.stderr}')
            if name == 'legacy': assert 'Imported private key was deleted' in result.stdout
    print('Signing bootstrap imported-key preservation, legacy-wipe reproduction, retries and relaunch tests passed')


if __name__ == '__main__': main()
