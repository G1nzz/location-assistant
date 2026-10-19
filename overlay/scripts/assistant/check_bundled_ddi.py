"""Install byte-exact DDI resources after Xcode, and verify the actual archive/IPA."""
import argparse
import copy
import hashlib
from pathlib import Path
import shutil
import stat
import tempfile
import zipfile

from prepare_ddi import ROOT, load_manifest, validate_manifest, verify_tree

PREFIX = "Payload/SideStore.app/AssistantDDI/"


def install(source, app, entries):
    verify_tree(source, entries)
    if app.is_symlink() or not app.is_dir():
        raise RuntimeError("Missing or unsafe unsigned app")
    destination = app / "AssistantDDI"
    if destination.exists() or destination.is_symlink():
        verify_tree(destination, entries)
        return
    # Xcode must not process these BuildManifest.plist files as app Info plists.
    shutil.copytree(source, destination)
    verify_tree(destination, entries)


def check_ipa(path, entries):
    expected = {entry["method"] + "/" + entry["name"]: entry for entry in entries}
    expected_directories = {"", "cryptex/", "personalized/"}
    seen = set()
    with zipfile.ZipFile(path) as package:
        for info in package.infolist():
            if not info.filename.startswith(PREFIX):
                continue
            name = info.filename[len(PREFIX):]
            if stat.S_ISLNK(info.external_attr >> 16):
                raise RuntimeError("IPA contains a developer image symlink")
            if info.is_dir():
                if name not in expected_directories:
                    raise RuntimeError("Unexpected developer image directory in IPA")
                continue
            if name not in expected or name in seen:
                raise RuntimeError("Unexpected or duplicate developer image in IPA")
            seen.add(name)
            entry = expected[name]
            if info.file_size != entry["size"]:
                raise RuntimeError("Incorrect developer image size in IPA")
            digest = hashlib.sha256()
            with package.open(info) as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
            if digest.hexdigest() != entry["sha256"]:
                raise RuntimeError("Incorrect developer image checksum in IPA")
    if seen != set(expected):
        raise RuntimeError("IPA is missing developer images")


def expect_failure(operation):
    try:
        operation()
    except (RuntimeError, OSError):
        return
    raise AssertionError("Invalid developer image resources were accepted")


def self_test(source, entries):
    verify_tree(source, entries)
    (ROOT / ".build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ddi-packaging-test-", dir=ROOT / ".build") as temporary:
        folder = Path(temporary)
        app = folder / "SideStore.app"
        app.mkdir()
        install(source, app, entries)
        bundle = app / "AssistantDDI"
        verify_tree(bundle, entries)
        package = folder / "test.ipa"
        with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_STORED) as zipped:
            for file in bundle.rglob("*"):
                if file.is_file():
                    zipped.write(file, PREFIX + file.relative_to(bundle).as_posix())
        check_ipa(package, entries)
        # Check same-size corruption as well as missing, extra and truncated data.
        test_file = bundle / "cryptex/BuildManifest.plist"
        original = test_file.read_bytes()
        test_file.write_bytes(bytes([original[0] ^ 1]) + original[1:])
        expect_failure(lambda: verify_tree(bundle, entries))
        test_file.write_bytes(original[:-1])
        expect_failure(lambda: verify_tree(bundle, entries))
        test_file.unlink()
        expect_failure(lambda: verify_tree(bundle, entries))
        test_file.write_bytes(original)
        extra = bundle / "unexpected.txt"
        extra.write_text("unexpected", encoding="utf-8")
        expect_failure(lambda: verify_tree(bundle, entries))
        extra.unlink()
        with zipfile.ZipFile(package, "a") as zipped:
            zipped.writestr(PREFIX + "../escape", b"bad")
        expect_failure(lambda: check_ipa(package, entries))
        import json
        manifest = json.loads((ROOT / "AltStore/LocationAssistant/AssistantDDIManifest.json").read_text(encoding="utf-8"))
        invalid = copy.deepcopy(manifest)
        invalid["files"][0]["name"] = "../BuildManifest.plist"
        expect_failure(lambda: validate_manifest(invalid))
        invalid = copy.deepcopy(manifest)
        invalid["files"].pop()
        expect_failure(lambda: validate_manifest(invalid))
    print("Bundled DDI packaging, integrity and failure checks passed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / ".build/bundled-ddi")
    parser.add_argument("--install-to", type=Path)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--ipa", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    entries = load_manifest()
    if not any((args.install_to, args.app, args.ipa, args.self_test)):
        parser.error("Select --install-to, --app, --ipa or --self-test")
    if args.self_test:
        self_test(args.source, entries)
    if args.install_to:
        install(args.source, args.install_to, entries)
    if args.app:
        verify_tree(args.app / "AssistantDDI", entries)
    if args.ipa:
        check_ipa(args.ipa, entries)
        print("Actual IPA developer image bytes verified (both methods, 8 files)")


if __name__ == "__main__":
    main()
