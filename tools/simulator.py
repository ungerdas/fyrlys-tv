#!/usr/bin/env python3
"""Finner (eller lager) en Apple TV-simulator som passer den valgte Xcode-en, og skriver «SIM_ID=<udid>»."""
import json
import re
import subprocess
import sys


def log(text):
    print(text, file=sys.stderr, flush=True)


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def version(text):
    return [int(x) for x in re.findall(r"\d+", text)]


def sdk_version():
    for sdk in json.loads(run("xcodebuild", "-showsdks", "-json")):
        if sdk.get("platform") == "appletvsimulator":
            return version(sdk.get("sdkVersion", ""))
    return None


def runtimes(sdk):
    found = []
    for runtime in json.loads(run("xcrun", "simctl", "list", "runtimes", "-j"))["runtimes"]:
        if runtime.get("platform") != "tvOS" or not runtime.get("isAvailable"):
            continue
        if sdk and version(runtime["version"])[:2] > sdk[:2]:
            continue
        found.append(runtime)
    return sorted(found, key=lambda r: version(r["version"]))


def main():
    sdk = sdk_version()
    log(f"tvOS-SDK i Xcode: {sdk}")
    found = runtimes(sdk)
    if not found:
        log("Ingen tvOS-simulator passer; laster ned (xcodebuild -downloadPlatform tvOS) …")
        subprocess.run(["xcodebuild", "-downloadPlatform", "tvOS"], check=True, stdout=sys.stderr)
        found = runtimes(sdk)
    if not found:
        sys.exit("Fant ingen tvOS-simulator")
    runtime = found[-1]
    log(f"Simulator: tvOS {runtime['version']} ({runtime['identifier']})")
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j"))["devices"]
    devices = devices.get(runtime["identifier"], [])
    pick = [d for d in devices if "4K" in d["name"]] or devices
    if pick:
        device = pick[-1]
        log(f"Bruker {device['name']} ({device['udid']})")
        udid = device["udid"]
    else:
        types = [t for t in runtime.get("supportedDeviceTypes", []) if "Apple TV" in t.get("name", "")]
        if not types:
            types = [t for t in json.loads(run("xcrun", "simctl", "list", "devicetypes", "-j"))["devicetypes"]
                     if "Apple TV" in t.get("name", "")]
        kind = ([t for t in types if "4K" in t["name"]] or types)[-1]
        udid = run("xcrun", "simctl", "create", "Fyrlys TV", kind["identifier"], runtime["identifier"]).strip()
        log(f"Laget {kind['name']} ({udid})")
    print(f"SIM_ID={udid}")


if __name__ == "__main__":
    main()
