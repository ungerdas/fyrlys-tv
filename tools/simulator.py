#!/usr/bin/env python3
"""Finner (eller lager) en simulator som passer den valgte Xcode-en, og skriver «<NAVN>=<udid>».

    python3 tools/simulator.py                       Apple TV 4K   → SIM_ID=…
    python3 tools/simulator.py iOS iPhone IPHONE_ID  en iPhone     → IPHONE_ID=…
    python3 tools/simulator.py iOS "iPhone Max" IPHONE_ID  en stor iPhone (Pro Max: vanlig bredde på tvers)
    python3 tools/simulator.py iOS iPad IPAD_ID      en iPad (11") → IPAD_ID=…
"""
import json
import re
import subprocess
import sys

SDKS = {"tvOS": "appletvsimulator", "iOS": "iphonesimulator"}


def log(text):
    print(text, file=sys.stderr, flush=True)


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def version(text):
    return [int(x) for x in re.findall(r"\d+", text)]


def sdk_version(platform):
    for sdk in json.loads(run("xcodebuild", "-showsdks", "-json")):
        if sdk.get("platform") == SDKS[platform]:
            return version(sdk.get("sdkVersion", ""))
    return None


def runtimes(platform, sdk):
    found = []
    for runtime in json.loads(run("xcrun", "simctl", "list", "runtimes", "-j"))["runtimes"]:
        if runtime.get("platform") != platform or not runtime.get("isAvailable"):
            continue
        if sdk and version(runtime["version"])[:2] > sdk[:2]:
            continue
        found.append(runtime)
    return sorted(found, key=lambda r: version(r["version"]))


def preferred(names, kind):
    """Den vi helst vil ha: Apple TV 4K; en vanlig iPhone (ikke Max, Plus, SE eller mini), eller en stor («iPhone
    Max»: Pro Max, ellers Max eller Plus); en iPad på 11 tommer."""
    if kind == "iPhone Max":
        return ([n for n in names if "Pro Max" in n] or [n for n in names if re.search(r"Max|Plus", n)]
                or preferred(names, "iPhone"))
    if kind == "Apple TV":
        return [n for n in names if "4K" in n] or names
    if kind == "iPhone":
        plain = [n for n in names if not re.search(r"Max|Plus|SE|mini", n)]
        return [n for n in plain if "Pro" in n] or plain or names
    if kind == "iPad":
        return [n for n in names if "11" in n] or [n for n in names if "Air" in n or "Pro" in n] or names
    return names


def main():
    platform = sys.argv[1] if len(sys.argv) > 1 else "tvOS"
    kind = sys.argv[2] if len(sys.argv) > 2 else "Apple TV"
    var = sys.argv[3] if len(sys.argv) > 3 else "SIM_ID"
    sdk = sdk_version(platform)
    log(f"{platform}-SDK i Xcode: {sdk}")
    found = runtimes(platform, sdk)
    if not found:
        log(f"Ingen {platform}-simulator passer; laster ned (xcodebuild -downloadPlatform {platform}) …")
        subprocess.run(["xcodebuild", "-downloadPlatform", platform], check=True, stdout=sys.stderr)
        found = runtimes(platform, sdk)
    if not found:
        sys.exit(f"Fant ingen {platform}-simulator")
    runtime = found[-1]
    log(f"Simulator: {platform} {runtime['version']} ({runtime['identifier']})")
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j"))["devices"]
    family = "iPhone" if kind == "iPhone Max" else kind
    devices = [d for d in devices.get(runtime["identifier"], []) if family in d["name"]]
    names = preferred([d["name"] for d in devices], kind)
    pick = [d for d in devices if d["name"] in names]
    if pick:
        device = pick[-1]
        log(f"Bruker {device['name']} ({device['udid']})")
        udid = device["udid"]
    else:
        types = [t for t in runtime.get("supportedDeviceTypes", []) if family in t.get("name", "")]
        if not types:
            types = [t for t in json.loads(run("xcrun", "simctl", "list", "devicetypes", "-j"))["devicetypes"]
                     if family in t.get("name", "")]
        if not types:
            sys.exit(f"Fant ingen enhetstype for {kind}")
        names = preferred([t["name"] for t in types], kind)
        chosen = [t for t in types if t["name"] in names][-1]
        udid = run("xcrun", "simctl", "create", f"Fyrlys {kind}", chosen["identifier"], runtime["identifier"]).strip()
        log(f"Laget {chosen['name']} ({udid})")
    print(f"{var}={udid}")


if __name__ == "__main__":
    main()
