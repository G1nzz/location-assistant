"""Regression guards for the reviewed startup/signing boundaries, not device tests."""
from pathlib import Path
import ast
import json

ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT/path).read_text(encoding='utf-8')
def body(text, name):
    a = text.index(name); a = text.index('{', a); i = a + 1; depth = 1
    while depth:
        depth += (text[i] == '{') - (text[i] == '}'); i += 1
    return text[a+1:i-1]

def main():
    app = read('AltStore/AppDelegate.swift')
    assert 'DatabaseManager.shared.start()' not in body(app, 'func application(_ application: UIApplication, didFinishLaunchingWithOptions')
    assert body(app, 'func open(_ url: URL) -> Bool').strip() == 'false'
    scene = read('AltStore/SceneDelegate.swift')
    assert 'exportPairingFile' not in scene and 'URLHandler.shared' not in scene and 'DatabaseManager.shared' not in scene
    signing = read('AltStore/LocationAssistant/AssistantSigningCoordinator.swift')
    account = body(signing, 'func signIn(presenting')
    assert 'prepareRuntime()' not in account
    assert 'skipDeviceRegistration: true, skipCertificateProvisioning: true' in account
    runtime = body(signing, 'private func prepareRuntime()')
    assert 'runtimeStarted' not in signing
    assert runtime.index('minimuxer.core.stop()') < runtime.index('startMinimuxer(pairingFile: pairing)')
    signin = read('SideStore/Core/Operations/StandaloneOperations/SignInOperation.swift')
    cached = signin[signin.index('if var session = AuthManager.shared.session'):signin.index('} else {\n                authResult =')]
    assert 'if !self.skipDeviceRegistration' in cached and 'registerCurrentDevice' in cached
    session = read('AltStore/LocationAssistant/AssistantSession.swift')
    start = body(session, 'func start(_ coordinate:')
    assert start.index('try await prepareDeveloperServices(ip: ip)') < start.index('setNeedsClear(true)') < start.index('AssistantNative.set(')
    assert 'Task.detached(priority: .utility)' in session
    assert 'preparationTask?.cancel()' in session
    for name in ['func downloadDeveloperImages()', 'private func downloadDeveloperImages(method:']:
        preload = body(session, name)
        assert 'AssistantNative' not in preload and 'native {' not in preload
        assert 'signIn' not in preload and 'CertificateManager' not in preload
    assert 'diagnostic = failure.diagnostic' in session
    assert 'func prepare(method:' in read('AltStore/LocationAssistant/AssistantDDIAssets.swift')
    assert 'recordNativeFailure(stage: "清除模拟"' in session
    assert 'pausesLocationUpdatesAutomatically = false' in session
    assert 'locationManagerDidPauseLocationUpdates' in session
    login_service = read('AltStore/LocationAssistant/AssistantLoginService.swift')
    assert login_service.count('try Task.checkCancellation()') >= 4
    settings = read('AltStore/LocationAssistant/AssistantSettingsController.swift')
    service_check = settings[settings.index('case 9, 10:'):settings.index('default: break')]
    assert 'guard AssistantLoginPolicy.usesCompatibleService' in service_check
    search = read('AltStore/LocationAssistant/AssistantLocationController.swift')
    assert 'selectedLabel.text = "搜索失败' not in search and 'selectedLabel.text = "未找到' not in search
    build = read('scripts/assistant/build.sh')
    assert '\n+' not in build
    assert '-disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile' in build
    assert 'if plugins.exists(): shutil.rmtree(plugins)' in build
    patched = read('Dependencies/SideSign/Sources/Anisette/RemoteAnisetteDataProvider.swift')
    assert 'while true' not in patched
    assert patched.count('AnisetteSocketDeadline(seconds: 20)') == 2
    assert patched.count('withTaskCancellationHandler') == 2
    lock = json.loads(read('upstream-lock.json'))
    assert lock['swiftpm_resolved_sha256']
    for directory in ['scripts/assistant']:
        for path in (ROOT/directory).glob('*.py'): ast.parse(path.read_text(encoding='utf-8'))
    print('Reviewed startup, account/device separation, preflight ordering, dependency lock and privacy contracts passed')

if __name__ == '__main__': main()
