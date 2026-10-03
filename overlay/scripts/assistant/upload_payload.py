"""Read only the explicitly exported public overlay for connector uploads."""
import base64
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3] / "location-assistant-publish"
files = sorted(path for path in ROOT.rglob("*") if path.is_file())
if len(sys.argv) == 1:
    def entry(path):
        content = path.read_bytes()
        blob = b"blob " + str(len(content)).encode() + b"\0" + content
        return {"path": str(path.relative_to(ROOT)).replace("\\", "/"), "bytes": len(content), "sha": hashlib.sha1(blob).hexdigest()}
    print(json.dumps([entry(path) for path in files]))
else:
    index, offset = map(int, sys.argv[1:3])
    payload = base64.b64encode(files[index].read_bytes()).decode("ascii")
    print(json.dumps({"part": payload[offset:offset+16000], "length": len(payload)}))
