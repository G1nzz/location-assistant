"""Fetch exact upstream sources into this workspace without using global caches."""
import hashlib
import json
import shutil
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def source(repository, commit, destination):
    if (destination / "Package.swift").exists(): return
    archive = ROOT / ".build/downloads" / (repository.replace("/", "-") + "-" + commit + ".zip")
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        with urllib.request.urlopen(f"https://codeload.github.com/{repository}/zip/{commit}", timeout=120) as response:
            with archive.open("wb") as output: shutil.copyfileobj(response, output)
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as zipped:
        root = zipped.namelist()[0].split("/")[0]
        for entry in zipped.infolist():
            relative = Path(entry.filename).relative_to(root)
            target = (destination / relative).resolve()
            if not target.is_relative_to(destination.resolve()): raise RuntimeError("Unsafe archive entry")
            if entry.is_dir(): target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with zipped.open(entry) as input_file, target.open("wb") as output: shutil.copyfileobj(input_file, output)

def main():
    lock = json.loads((ROOT / "upstream-lock.json").read_text())
    for dependency in lock["dependencies"]:
        source(dependency["repository"], dependency["commit"], ROOT / dependency["path"])
    vendor = ROOT / "Vendor/idevice"
    library = vendor / "libidevice_ffi.a"
    if not library.exists():
        vendor.mkdir(parents=True, exist_ok=True)
        url = f'https://raw.githubusercontent.com/StikDebug/StikDebug/{lock["stikdebug"]["commit"]}/StikDebug/idevice/libidevice_ffi.a'
        with urllib.request.urlopen(url, timeout=120) as response, library.open("wb") as output: shutil.copyfileobj(response, output)
    if hashlib.sha256(library.read_bytes()).hexdigest() != lock["stikdebug"]["ffi_sha256"]:
        raise RuntimeError("StikDebug FFI checksum mismatch")

if __name__ == "__main__": main()
