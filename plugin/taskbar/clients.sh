#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

CHROME_CLASS_RE = re.compile(r"^chrome-(.+)$", re.I)
PROFILE_SUFFIX_RE = re.compile(r"-(?:Default|Profile_\d+)$", re.I)
URL_RE = re.compile(r"https?://[^\s\"']+", re.I)
APP_FLAG_RE = re.compile(r"--app=(\S+)")
HANDLER_RE = re.compile(r"omarchy-webapp-handler-[^\s]+")


def desktop_dirs():
    dirs = []
    data_home = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    dirs.append(Path(data_home) / "applications")
    for raw in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
        raw = raw.strip()
        if raw:
            dirs.append(Path(raw) / "applications")
    omarchy = Path("/usr/share/omarchy/applications")
    if omarchy.is_dir() and omarchy not in dirs:
        dirs.append(omarchy)
    return dirs


def norm_host(netloc):
    host = str(netloc or "").strip().lower()
    if host.startswith("www."):
        host = host[4:]
    return host


def urls_from_exec(exec_line):
    urls = URL_RE.findall(exec_line or "")
    m = APP_FLAG_RE.search(exec_line or "")
    if m:
        url = m.group(1).strip().strip('"').strip("'")
        if url and url not in urls:
            urls.append(url)
    return urls


def urls_from_handler(exec_line):
    m = HANDLER_RE.search(exec_line or "")
    if not m:
        return []
    name = m.group(0)
    path = None
    for directory in os.environ.get("PATH", "").split(":"):
        candidate = Path(directory) / name
        if candidate.is_file():
            path = candidate
            break
    if path is None:
        fallback = Path("/usr/share/omarchy/bin") / name
        if fallback.is_file():
            path = fallback
    if path is None:
        return []
    try:
        return URL_RE.findall(path.read_text(errors="ignore"))
    except OSError:
        return []


def load_webapps_by_host():
    """Map normalized URL host -> desktop id. User dirs win over system dirs."""
    by_host = {}
    seen_files = set()
    for directory in desktop_dirs():
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob("*.desktop")):
            key = str(path.resolve()) if path.exists() else str(path)
            if key in seen_files:
                continue
            seen_files.add(key)
            try:
                text = path.read_text(errors="ignore")
            except OSError:
                continue
            exec_m = re.search(r"^Exec=(.*)$", text, re.M)
            if not exec_m:
                continue
            exec_line = exec_m.group(1)
            if (
                "omarchy-launch-webapp" not in exec_line
                and "--app=" not in exec_line
                and "omarchy-webapp-handler-" not in exec_line
            ):
                continue
            desktop_id = path.stem
            urls = urls_from_exec(exec_line) or urls_from_handler(exec_line)
            for url in urls:
                try:
                    parsed = urlparse(url if "://" in url else "https://" + url)
                except ValueError:
                    continue
                host = norm_host(parsed.netloc)
                if host and host not in by_host:
                    by_host[host] = desktop_id
    return by_host


def host_from_chrome_class(cls):
    m = CHROME_CLASS_RE.match(cls or "")
    if not m:
        return ""
    body = PROFILE_SUFFIX_RE.sub("", m.group(1))
    return norm_host(body.split("_", 1)[0])


def host_from_cmdline(cmd):
    m = APP_FLAG_RE.search(cmd or "")
    if not m:
        return ""
    url = m.group(1).strip().strip('"').strip("'")
    if not url:
        return ""
    try:
        parsed = urlparse(url if "://" in url else "https://" + url)
    except ValueError:
        return ""
    return norm_host(parsed.netloc)


def chrome_webapp_id(cls, cmd, webapps):
    # Prefer the window class: Chromium keeps one process for several --app
    # windows, so /proc/pid/cmdline is the first app and would mis-group the rest.
    host = host_from_chrome_class(cls) or host_from_cmdline(cmd)
    if not host:
        return ""
    return webapps.get(host) or ""


def identity_for(cls, cmd, title, webapps):
    cl = cls.lower()
    cmdl = cmd.lower()
    title_l = title.lower()

    if cl in ("herdr", "org.omarchy.herdr") or "-e herdr" in cmdl or cmdl.endswith(" herdr") or cmdl.endswith("/herdr"):
        return "herdr"
    if "spotify" in cl or "spotify" in title_l:
        return "spotify"
    if cl in ("org.gnome.nautilus", "nautilus"):
        return "org.gnome.nautilus"
    if cl == "chromium":
        return "chromium"
    if cl == "foot":
        return "foot"
    if cl in ("jetbrains-idea", "idea") or "intellij" in cl:
        return "idea"
    if cl in ("dbeaver",) or "/usr/lib/dbeaver" in cmdl or "dbeaver" in title_l:
        return "dbeaver"
    if cl.startswith("chrome-"):
        mapped = chrome_webapp_id(cls, cmd, webapps)
        if mapped:
            return mapped
        return cls
    return cl


def main():
    try:
        raw = subprocess.check_output(["hyprctl", "clients", "-j"], text=True)
        clients = json.loads(raw)
    except Exception:
        print("[]")
        sys.exit(0)

    webapps = load_webapps_by_host()
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
        title = str(c.get("title") or "")
        ident = identity_for(cls, cmd, title, webapps)

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


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--dump-webapps":
        for host, desktop_id in sorted(load_webapps_by_host().items()):
            print("%s\t%s" % (host, desktop_id))
        sys.exit(0)
    main()
