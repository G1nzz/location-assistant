"""Fail closed if distribution settings or vendored inputs do not match the plan."""
from pathlib import Path
import hashlib
import json
import plistlib

ROOT = Path(__file__).resolve().parents[2]

def main():
    lock = json.loads((ROOT / "upstream-lock.json").read_text())
    assert lock["sidestore"]["commit"] == "6032424a0e56c1c319762e786099bdd9186a238b"
    assert lock["stikdebug"]["commit"] == "4bdfc92aa7cebd7a534f1e1ef56415f5727402de"
    library = ROOT / "Vendor/idevice/libidevice_ffi.a"
    assert hashlib.sha256(library.read_bytes()).hexdigest() == lock["stikdebug"]["ffi_sha256"]
    plist = plistlib.loads((ROOT / "AltStore/Info.plist").read_bytes())
    assert plist["ALTDeviceID"] == "XXXXXXXX-XXXXXXXXXXXXXXXX", "Do not publish real device UDIDs"
    assert plist["ALTPairingFile"] == "<insert pairing file here>", "Do not embed pairing secrets"
    assert "location" in plist["UIBackgroundModes"]
    assert plist["CFBundleDisplayName"] == "定位助手"
    assert "CFBundleDocumentTypes" not in plist
    assert "BASE_BUNDLE_ID = com.locationassistant.personal" in (ROOT / "Build.xcconfig").read_text()
    assert '"com.SideStore.SideStore"' not in (ROOT / "Shared/Extensions/Bundle+AltStore.swift").read_text()
    for name in ["AltStore/Resources/ReleaseEntitlements.plist", "AltWidget/Resources/ReleaseEntitlements.plist"]:
        assert "com.SideStore.SideStore" not in (ROOT / name).read_text()
    for path in ROOT.rglob("*.plist"):
        if ".build" in path.parts or "Dependencies" in path.parts: continue
        try: plistlib.loads(path.read_bytes())
        except Exception as error: raise AssertionError(f"Invalid plist: {path.relative_to(ROOT)}") from error
    print("Pinned input, package identity, pairing privacy and plist checks passed")

if __name__ == "__main__": main()
