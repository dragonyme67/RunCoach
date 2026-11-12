"""Print the UDID of the largest available iPhone simulator on the newest iOS runtime."""
import json
import subprocess
import sys

raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
devices = json.loads(raw)["devices"]

best = None
for runtime in sorted(devices, reverse=True):
    if "iOS" not in runtime:
        continue
    for dev in devices[runtime]:
        name = dev["name"]
        if not name.startswith("iPhone"):
            continue
        score = 2 if ("Plus" in name or "Pro Max" in name) else 1
        if best is None or score > best[0]:
            best = (score, dev["udid"], name, runtime)
    if best:
        break

assert best is not None, "no iPhone simulator available"
sys.stderr.write("simulator: %s (%s)\n" % (best[2], best[3]))
print(best[1])
