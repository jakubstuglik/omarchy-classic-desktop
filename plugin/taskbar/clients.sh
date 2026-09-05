#!/usr/bin/env python3
import json
import os
import subprocess
import sys

try:
    raw = subprocess.check_output(["hyprctl", "clients", "-j"], text=True)
    clients = json.loads(raw)
except Exception:
    print("[]")
    sys.exit(0)

out = []
for c in clients:
    pid = c.get("pid") or 0
    cmd = ""
    try:
        with open("/proc/%s/cmdline" % pid, "rb") as fh:
            cmd = fh.read().replace(b"\0", b" ").decode("utf-8", "replace").strip()
    except Exception:
        pass

    cls = str(c.get("class") or "")
    cl = cls.lower()
    cmdl = cmd.lower()
    title = str(c.get("title") or "")

    if cl in ("herdr", "org.omarchy.herdr") or "-e herdr" in cmdl or cmdl.endswith(" herdr") or cmdl.endswith("/herdr"):
        ident = "herdr"
    elif "spotify" in cl or "spotify" in title.lower():
        ident = "spotify"
    elif cl in ("org.gnome.nautilus", "nautilus"):
        ident = "org.gnome.nautilus"
    elif cl == "chromium":
        ident = "chromium"
    elif cl == "foot":
        ident = "foot"
    elif cl in ("jetbrains-idea", "idea") or "intellij" in cl:
        ident = "idea"
    elif cl in ("dbeaver",) or "/usr/lib/dbeaver" in cmdl or "dbeaver" in title.lower():
        ident = "dbeaver"
    else:
        ident = cl

    ws = c.get("workspace") or {}
    addr = str(c.get("address") or "")
    if addr and not addr.startswith("0x"):
        addr = "0x" + addr

    out.append({
        "address": addr,
        "class": cls,
        "title": title,
        "pid": pid,
        "identity": ident,
        "minimized": ws.get("name") == "special:minimized",
    })

print(json.dumps(out))
