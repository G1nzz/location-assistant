"""Keep renewal inside the serialized assistant flow; expose no IPA/JIT shortcuts."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def replace_body(content, marker, body, new_marker=None):
    start = content.index(marker)
    opening = content.index("{", start + len(marker))
    depth = 1
    end = opening + 1
    while depth:
        if content[end] == "{": depth += 1
        elif content[end] == "}": depth -= 1
        end += 1
    header = content[start:opening]
    if new_marker and new_marker not in header: header = header.replace(marker, new_marker)
    return content[:start] + header + "{\n" + body + "\n    }" + content[end:]

def main():
    path = ROOT / "AltStore/Intents/App Intents/RefreshAllAppsIntent.swift"
    content = path.read_text(encoding="utf-8")
    # There are two retained AppIntent types, installation and refresh.
    marker = "func perform() async throws -> some IntentResult"
    for name, message in [("InstallIPAIntent", "本版本不提供其他 IPA 安装。"), ("RefreshAllAppsIntent", "请打开定位助手，在续签页手动刷新自身签名。")]:
        start = content.index(f"struct {name}:")
        content = content[:start] + replace_body(content[start:], marker, f'        return .result(dialog: "{message}")', marker + " & ProvidesDialog")
    content = content.replace('static var openAppWhenRun = false', 'static var openAppWhenRun = true')
    if "static var isDiscoverable" not in content:
        content = content.replace('static var title: LocalizedStringResource = "Install IPA"', 'static var isDiscoverable: Bool { false }\n    static var title: LocalizedStringResource = "Install IPA"')
        content = content.replace('static let intentClassName = "RefreshAllIntent"', 'static var isDiscoverable: Bool { false }\n    static let intentClassName = "RefreshAllIntent"')
    path.write_text(content, encoding="utf-8")
    path = ROOT / "AltStore/Intents/App Intents/AppShortcuts.swift"
    content = path.read_text(encoding="utf-8")
    if "@available" in content:
        path.write_text(content[:content.index("@available")] + "// This assistant does not register automatic App Shortcuts.\n", encoding="utf-8")
    path = ROOT / "AltStore/Intents/Legacy/IntentHandler.swift"
    content = path.read_text(encoding="utf-8")
    for name in ["confirm", "handle"]:
        marker = f"func {name}(intent: RefreshAllIntent, completion: @escaping (RefreshAllIntentResponse) -> Void)"
        content = replace_body(content, marker, '        completion(RefreshAllIntentResponse.failure(localizedDescription: "请在定位助手的续签页手动刷新。"))')
    path.write_text(content, encoding="utf-8")

if __name__ == "__main__": main()
