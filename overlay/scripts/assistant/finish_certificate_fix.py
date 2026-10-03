"""One-time local migration; kept in source for auditability."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
path = ROOT / "SideStore/Core/Operations/StandaloneOperations/SignInOperation.swift"
text = path.read_text(encoding="utf-8")
start = text.find("    private func replaceCertificate(")
if start >= 0:
    end = text.index("    @discardableResult", start)
    text = text[:start] + text[end:]
    path.write_text(text, encoding="utf-8")
