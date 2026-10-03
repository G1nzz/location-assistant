"""Recreate the complete build tree from pinned SideStore plus this public overlay."""
from pathlib import Path
import json
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    lock = json.loads((ROOT / "upstream-lock.json").read_text())
    commit = lock["sidestore"]["commit"]
    project = ROOT / "project"
    downloads = ROOT / ".build/downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    archive = downloads / f"SideStore-{commit}.zip"
    if not archive.exists():
        with urllib.request.urlopen(f"https://codeload.github.com/SideStore/SideStore/zip/{commit}", timeout=120) as response, archive.open("wb") as out:
            shutil.copyfileobj(response, out)
    project.mkdir(exist_ok=True)
    with zipfile.ZipFile(archive) as zipped:
        root = zipped.namelist()[0].split("/")[0]
        for entry in zipped.infolist():
            relative = Path(entry.filename).relative_to(root)
            target = (project / relative).resolve()
            if not target.is_relative_to(project.resolve()): raise RuntimeError("Unsafe archive entry")
            if entry.is_dir(): target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with zipped.open(entry) as inp, target.open("wb") as out: shutil.copyfileobj(inp, out)
    shutil.copytree(ROOT / "overlay", project, dirs_exist_ok=True)
    print(f"Materialized SideStore {commit} with assistant overlay")

if __name__ == "__main__": main()
