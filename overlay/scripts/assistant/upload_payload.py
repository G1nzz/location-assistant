"""Read only the explicitly exported public overlay for connector uploads."""
import base64
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3] / "location-assistant-publish"
files = sorted(path for path in ROOT.rglob("*") if path.is_file())
if len(sys.argv) == 1:
    print(json.dumps([{"path": str(path.relative_to(ROOT)).replace("\\", "/"), "bytes": path.stat().st_size} for path in files]))
else:
    index, offset = map(int, sys.argv[1:3])
    payload = base64.b64encode(files[index].read_bytes()).decode("ascii")
    print(json.dumps({"part": payload[offset:offset+16000], "length": len(payload)}))
