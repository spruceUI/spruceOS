#!/usr/bin/env python3
"""Copy the third-party notices of a Qt source tree into a bundle's licence folder.

usage: qt-attributions.py QT_SOURCE_DIR OUT_DIR

Every qt_attribution.json outside tests, examples and docs names a component Qt carries, with
its licence and licence files. OUT_DIR gets ATTRIBUTIONS.txt (one block per component) and the
licence files as <Id>-<file>. Components the static build leaves out are listed as well: listing
more than is linked is harmless, missing one is not.
"""
import json
import os
import shutil
import sys


def entries(path):
    with open(path, encoding="utf-8") as fh:
        data = json.loads(fh.read(), strict=False)
    return data if isinstance(data, list) else [data]


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    blocks = []
    for root, dirs, files in os.walk(src):
        dirs[:] = sorted(d for d in dirs if d not in ("tests", "examples", "doc"))
        if "qt_attribution.json" not in files:
            continue
        for e in entries(os.path.join(root, "qt_attribution.json")):
            ident = e.get("Id") or e.get("Name", "unknown").replace(" ", "-").lower()
            names = e.get("LicenseFiles") or ([e["LicenseFile"]] if e.get("LicenseFile") else [])
            copied = []
            for name in names:
                p = os.path.normpath(os.path.join(root, name))
                if os.path.isfile(p):
                    target = f"{ident}-{os.path.basename(name)}"
                    shutil.copyfile(p, os.path.join(out, target))
                    copied.append(target)
            copyright_ = e.get("Copyright", "")
            if isinstance(copyright_, list):
                copyright_ = "\n".join(copyright_)
            lines = [f"{e.get('Name', ident)} {e.get('Version', '')}".rstrip(),
                     f"  in Qt: {os.path.relpath(root, src)}",
                     f"  licence: {e.get('License', '?')} ({e.get('LicenseId', '?')})"]
            lines += [f"  {line.strip()}" for line in str(copyright_).splitlines() if line.strip()]
            lines += [f"  text: {c}" for c in copied]
            blocks.append("\n".join(lines))
    with open(os.path.join(out, "ATTRIBUTIONS.txt"), "w", encoding="utf-8") as fh:
        fh.write("Third-party code in the Qt sources Skyscraper was built from (from qt_attribution.json).\n\n")
        fh.write("\n\n".join(blocks) + "\n")
    print(f"{len(blocks)} components")


if __name__ == "__main__":
    main()
