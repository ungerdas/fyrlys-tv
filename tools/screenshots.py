#!/usr/bin/env python3
"""Henter skjermbildene ut av testresultatet: python3 tools/screenshots.py build/Resultat.xcresult build/bilder

Bildene får navnet testen ga dem («02-tv.png»); bilder XCTest tok ved en feil, heter «feil-<test>-<n>.png».
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


def main():
    result, out = Path(sys.argv[1]), Path(sys.argv[2])
    if not result.exists():
        print(f"Ingen {result} (bygget feilet før testene?)")
        return
    raw = out / "raw"
    shutil.rmtree(raw, ignore_errors=True)
    raw.mkdir(parents=True)
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                    "--output-path", str(raw)], check=True)
    manifest = json.loads((raw / "manifest.json").read_text())
    count = 0
    for test in manifest:
        test_name = re.sub(r"\W+", "-", test.get("testIdentifier", "test")).strip("-")
        for n, attachment in enumerate(test.get("attachments", [])):
            source = raw / attachment["exportedFileName"]
            suffix = source.suffix or ".png"
            if attachment.get("isAssociatedWithFailure"):
                name = f"feil-{test_name}-{n}{suffix}"
            else:
                human = attachment.get("suggestedHumanReadableName") or source.name
                name = human.split("_")[0] + suffix
            shutil.copy(source, out / name)
            count += 1
    shutil.rmtree(raw, ignore_errors=True)
    print(f"{count} skjermbilder i {out}")
    for file in sorted(out.iterdir()):
        print(" ", file.name)


if __name__ == "__main__":
    main()
