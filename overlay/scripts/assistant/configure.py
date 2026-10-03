"""Apply deterministic project settings; run after fetching the pinned upstream tree."""
from pathlib import Path
import json
import plistlib
import re

ROOT = Path(__file__).resolve().parents[2]

def main():
    project = ROOT / "AltStore.xcodeproj/project.pbxproj"
    text = project.read_text(encoding="utf-8")
    # Synchronized AltStore group automatically includes the assistant Swift files.
    for config_id in ["BFD2477F2284B9A700981D42", "BFD247802284B9A700981D42"]:
        pattern = rf"({config_id} /\* (?:Debug|Release) \*/ = \{{.*?buildSettings = \{{)(.*?)(\n\t\t\t\}};)"
        match = re.search(pattern, text, re.S)
        if not match: raise RuntimeError(f"Missing app configuration: {config_id}")
        settings = match.group(2)
        settings = settings.replace('LIBRARY_SEARCH_PATHS = "$(inherited)";', 'LIBRARY_SEARCH_PATHS = "$(inherited) $(SRCROOT)/Vendor/idevice";')
        settings = settings.replace('"-lidevice_ffi",', '"$(SRCROOT)/Vendor/idevice/libidevice_ffi.a",')
        if '"$(SRCROOT)/Vendor/idevice/libidevice_ffi.a"' not in settings:
            settings = settings.replace('"-w",', '"-w",\n\t\t\t\t\t"$(SRCROOT)/Vendor/idevice/libidevice_ffi.a",')
        settings = settings.replace('IPHONEOS_DEPLOYMENT_TARGET = 15.0;', 'IPHONEOS_DEPLOYMENT_TARGET = 17.4;')
        settings = settings.replace('TARGETED_DEVICE_FAMILY = "1,2,3";', 'TARGETED_DEVICE_FAMILY = "1,2";')
        settings = settings.replace('SUPPORTED_PLATFORMS = "appletvos appletvsimulator iphoneos iphonesimulator";', 'SUPPORTED_PLATFORMS = "iphoneos";')
        if "SWIFT_INCLUDE_PATHS" not in settings:
            settings += '\n\t\t\t\tSWIFT_INCLUDE_PATHS = "$(inherited) $(SRCROOT)/Vendor/idevice";\n\t\t\t\tHEADER_SEARCH_PATHS = "$(inherited) $(SRCROOT)/Vendor/idevice";'
        text = text[:match.start(2)] + settings + text[match.end(2):]
    project.write_text(text, encoding="utf-8")
    build = ROOT / "Build.xcconfig"
    text = build.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^MARKETING_VERSION = .*", "MARKETING_VERSION = 0.1.0", text)
    text = re.sub(r"(?m)^CURRENT_PROJECT_VERSION = .*", "CURRENT_PROJECT_VERSION = 1", text)
    text = re.sub(r"(?m)^ORG_IDENTIFIER = .*", "ORG_IDENTIFIER = com.locationassistant", text)
    text = re.sub(r"(?m)^BASE_BUNDLE_ID\s*= .*", "BASE_BUNDLE_ID = com.locationassistant.personal", text)
    build.write_text(text, encoding="utf-8")
    plist_path = ROOT / "AltStore/Info.plist"
    plist = plistlib.loads(plist_path.read_bytes())
    plist["CFBundleDisplayName"] = "定位助手"
    plist["NSLocationWhenInUseUsageDescription"] = "仅在模拟期间维持本设备连接，便于切换到地图 App 验证。"
    plist["NSLocationAlwaysAndWhenInUseUsageDescription"] = "模拟期间维持后台设备连接；清除模拟后停止后台定位。"
    plist["NSLocalNetworkUsageDescription"] = "通过 LocalDevVPN 连接本设备，执行定位模拟与自身签名刷新。"
    if "location" not in plist["UIBackgroundModes"]: plist["UIBackgroundModes"].append("location")
    plist["CFBundleURLTypes"][0]["CFBundleURLSchemes"] = ["locationassistant"]
    # Remove IPA opening from the public assistant UI. SideStore backend remains intact.
    plist.pop("CFBundleDocumentTypes", None)
    plist_path.write_bytes(plistlib.dumps(plist, sort_keys=False))
    identity = ROOT / "Shared/Extensions/Bundle+AltStore.swift"
    identity.write_text(identity.read_text(encoding="utf-8").replace('"com.SideStore.SideStore"', '"com.locationassistant.personal"'), encoding="utf-8")
    for name in ["AltStore/Resources/ReleaseEntitlements.plist", "AltWidget/Resources/ReleaseEntitlements.plist"]:
        path = ROOT / name
        path.write_text(path.read_text(encoding="utf-8").replace("com.SideStore.SideStore", "com.locationassistant.personal"), encoding="utf-8")

if __name__ == "__main__": main()
