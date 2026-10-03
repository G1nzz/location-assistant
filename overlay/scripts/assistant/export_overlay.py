"""Export only publishable source changes, never runtime data or signing material."""
from pathlib import Path
import json
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
FILES = [
    "AltStore/Authentication/Authentication.storyboard",
    "Shared/Extensions/Bundle+AltStore.swift",
    "SideStore/Core/Pairing/PairingFileManager.swift",
    "SideStore/Core/Operations/StandaloneOperations/SignInOperation.swift",
    "SideStore/Utils/importexport/ImportExport.swift",
    "AltStore/Intents/App Intents/RefreshAllAppsIntent.swift",
    "AltStore/Intents/App Intents/AppShortcuts.swift",
    "AltStore/Intents/Legacy/IntentHandler.swift",
    "AltStore/Resources/ReleaseEntitlements.plist", "AltWidget/Resources/ReleaseEntitlements.plist",
    "AltStore/TabBarController.swift", "AltStore/AppDelegate.swift",
    "AltStore/Managing Apps/AppManager.swift", "AltStore/Info.plist",
    "AltStore.xcodeproj/project.pbxproj", "Build.xcconfig",
    "Vendor/idevice/idevice.h", "Vendor/idevice/module.modulemap", "Vendor/StikDebug-LICENSE",
    "LICENSE", "THIRD_PARTY_NOTICES.md", "upstream-lock.json",
]

def main(destination):
    destination.mkdir(parents=True, exist_ok=True)
    selected = list(FILES)
    for directory in ["AltStore/LocationAssistant", "AltStore/zh-Hans.lproj", "scripts/assistant", "tests/assistant", "docs"]:
        selected += [str(path.relative_to(ROOT)).replace("\\", "/") for path in (ROOT / directory).rglob("*") if path.is_file()]
    for name in sorted(set(selected)):
        target = destination / "overlay" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
    (destination / ".github/workflows").mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / ".github/workflows/assistant.yml", destination / ".github/workflows/assistant.yml")
    (destination / "scripts").mkdir(exist_ok=True)
    shutil.copy2(ROOT / "scripts/assistant/materialize.py", destination / "scripts/materialize.py")
    shutil.copy2(ROOT / "docs/仓库说明.md", destination / "README.md")
    for name in ["LICENSE", "THIRD_PARTY_NOTICES.md", "upstream-lock.json"]: shutil.copy2(ROOT / name, destination / name)
    (destination / ".gitignore").write_text("project/\n.build/\n*.ipa\n*.mobiledevicepairing\n*.p12\n*.p8\n*.mobileprovision\nCodeSigning.xcconfig\n__pycache__/\n", encoding="utf-8")
    # Upload callers consume this manifest, not arbitrary files from the workspace.
    files = [str(path.relative_to(destination)).replace("\\", "/") for path in destination.rglob("*") if path.is_file()]
    print(json.dumps({"files": sorted(files), "count": len(files)}, ensure_ascii=False))

if __name__ == "__main__": main(Path(sys.argv[1]).resolve())
