"""Fetch and verify the pinned public developer images outside the Xcode group."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = {
    "personalized": {"BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"},
    "cryptex": {"BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache",
                "Image.dmg.cryptex_info", "Image.dmg.root_hash"},
}


def load_manifest():
    manifest = json.loads((ROOT / "AltStore/LocationAssistant/AssistantDDIManifest.json").read_text(encoding="utf-8"))
    locked = json.loads((ROOT / "upstream-lock.json").read_text(encoding="utf-8"))["developer_disk_image"]
    if manifest != locked:
        raise RuntimeError("Bundled DDI manifest differs from upstream lock")
    validate_manifest(manifest)
    return manifest["files"]


def validate_manifest(manifest):
    if manifest.get("repository") != "doronz88/DeveloperDiskImage" or not re.fullmatch(r"[0-9a-f]{40}", manifest.get("commit", "")):
        raise RuntimeError("Invalid developer image source")
    seen = set()
    for entry in manifest["files"]:
        method, name = entry["method"], entry["name"]
        if method not in EXPECTED or name not in EXPECTED[method] or (method, name) in seen:
            raise RuntimeError("Unexpected or duplicate developer image path")
        seen.add((method, name))
        folder = "Xcode_iOS_DDI_" + ("Cryptex" if method == "cryptex" else "Personalized")
        expected_url = f'https://raw.githubusercontent.com/{manifest["repository"]}/{manifest["commit"]}/PersonalizedImages/{folder}/{name}'
        if entry["url"] != expected_url or type(entry["size"]) is not int or not 0 < entry["size"] <= 32 * 1024 * 1024:
            raise RuntimeError("Invalid developer image URL or size")
        if not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"]):
            raise RuntimeError("Invalid developer image checksum")
    if seen != {(method, name) for method, names in EXPECTED.items() for name in names}:
        raise RuntimeError("Incomplete developer image manifest")


def verify_file(path, entry):
    if path.is_symlink() or not path.is_file() or path.stat().st_size != entry["size"]:
        raise RuntimeError(f'Missing or incorrect size: {entry["method"]}/{entry["name"]}')
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != entry["sha256"]:
        raise RuntimeError(f'Incorrect checksum: {entry["method"]}/{entry["name"]}')


def verify_tree(folder, entries):
    if folder.is_symlink() or not folder.is_dir():
        raise RuntimeError("Missing or unsafe developer image directory")
    expected = {f'{entry["method"]}/{entry["name"]}' for entry in entries}
    actual = set()
    for path in folder.rglob("*"):
        relative = path.relative_to(folder).as_posix()
        if path.is_symlink() or not path.resolve().is_relative_to(folder.resolve()):
            raise RuntimeError("Unsafe developer image path")
        if path.is_dir():
            if relative not in EXPECTED:
                raise RuntimeError("Unexpected developer image directory")
        elif path.is_file():
            actual.add(relative)
        else:
            raise RuntimeError("Unexpected developer image file type")
    if actual != expected:
        raise RuntimeError("Developer image file set differs from manifest")
    for entry in entries:
        verify_file(folder / entry["method"] / entry["name"], entry)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        raise RuntimeError("Developer image redirects are not permitted")


def fetch_file(entry, target):
    opener = urllib.request.build_opener(NoRedirect)
    fd, temporary_name = tempfile.mkstemp(prefix=".ddi-", dir=target.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "wb") as output:
            started = time.monotonic()
            request = urllib.request.Request(entry["url"], headers={"User-Agent": "LocationAssistant-build"})
            with opener.open(request, timeout=30) as response:
                if response.status != 200:
                    raise RuntimeError("Developer image download did not return HTTP 200")
                length = response.headers.get("Content-Length")
                if length is not None and int(length) != entry["size"]:
                    raise RuntimeError("Developer image response size differs from manifest")
                received = 0
                while True:
                    chunk = response.read(min(1024 * 1024, entry["size"] - received + 1))
                    if not chunk:
                        break
                    received += len(chunk)
                    if received > entry["size"] or time.monotonic() - started > 180:
                        raise RuntimeError("Developer image transfer limit exceeded")
                    output.write(chunk)
        verify_file(temporary, entry)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)


def prepare(output, fixtures=None):
    entries = load_manifest()
    if fixtures is not None:
        verify_tree(fixtures, entries)
    if output.is_symlink():
        raise RuntimeError("Unsafe developer image output directory")
    output.mkdir(parents=True, exist_ok=True)
    for entry in entries:
        target = output / entry["method"] / entry["name"]
        if target.parent.is_symlink() or target.is_symlink():
            raise RuntimeError("Unsafe developer image output path")
        target.parent.mkdir(exist_ok=True)
        if fixtures is not None:
            source = fixtures / entry["method"] / entry["name"]
            if source.resolve() != target.resolve():
                shutil.copyfile(source, target)
        else:
            try:
                verify_file(target, entry)
            except RuntimeError:
                fetch_file(entry, target)
        verify_file(target, entry)
    verify_tree(output, entries)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/bundled-ddi")
    parser.add_argument("--fixtures", type=Path, default=os.environ.get("ASSISTANT_DDI_FIXTURES"))
    args = parser.parse_args()
    prepare(args.output, Path(args.fixtures) if args.fixtures else None)
    print("Pinned public developer images prepared and verified (8 files)")


if __name__ == "__main__":
    main()
