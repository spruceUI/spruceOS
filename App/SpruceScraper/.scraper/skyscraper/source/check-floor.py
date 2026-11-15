#!/usr/bin/env python3
"""Fail unless an aarch64 program loads on every board of the fleet census (docs/NATIVE-LIBRARIES.md).

usage: check-floor.py --readelf READELF --zlib LIBZ_FLOOR [--forbid TEXT ...] FILE...

Rules, from the firmware of the boards the census covers:
- DT_NEEDED only libraries every board's firmware serves: glibc's own, libstdc++, libgcc_s, zlib;
  interpreter /lib/ld-linux-aarch64.so.1; no RPATH or RUNPATH
- no symbol version newer than the oldest firmware has: GLIBC_2.33, GLIBCXX_3.4.28, CXXABI_1.3.12
  and GCC_7.0.0 (TrimUI); only ZLIB_ versions the floor zlib (LIBZ_FLOOR, 1.2.8) defines
- none of the --forbid strings (build host paths) inside the file
Prints what each file needs; exits 1 on any violation.
"""
import argparse
import re
import subprocess
import sys

ALLOWED = {"libc.so.6", "libm.so.6", "libpthread.so.0", "libdl.so.2", "librt.so.1",
           "libstdc++.so.6", "libgcc_s.so.1", "libz.so.1", "ld-linux-aarch64.so.1"}
CEILING = {"GLIBC": (2, 33), "GLIBCXX": (3, 4, 28), "CXXABI": (1, 3, 12), "GCC": (7, 0, 0)}
INTERP = "/lib/ld-linux-aarch64.so.1"


def split_version(name):
    """'GLIBC_2.33' -> ('GLIBC', (2, 33)); a name without a numeric part gets None."""
    family, _, number = name.partition("_")
    try:
        return family, tuple(int(x) for x in number.split("."))
    except ValueError:
        return family, None


def readelf(tool, *args):
    return subprocess.run([tool, "-W", *args], check=True, capture_output=True, text=True).stdout


def version_sections(tool, path):
    """(definitions, {library: {versions}}) from readelf -V."""
    out = readelf(tool, "-V", path)
    defs, needs, current = set(), {}, None
    section = None
    for line in out.splitlines():
        if line.startswith("Version definition section"):
            section = "def"
        elif line.startswith("Version needs section"):
            section = "need"
        elif line.startswith("Version symbols section"):
            section = None
        elif section == "def":
            m = re.search(r"Index: \d+\s+Cnt: \d+\s+Name: (\S+)", line)
            if m:
                defs.add(m.group(1))
        elif section == "need":
            m = re.search(r"File: (\S+)", line)
            if m:
                current = m.group(1)
                needs.setdefault(current, set())
                continue
            m = re.search(r"Name: (\S+)", line)
            if m and current:
                needs[current].add(m.group(1))
    return defs, needs


def check(tool, path, zlib_defs, forbid):
    problems = []
    header = readelf(tool, "-h", path)
    elf_class = re.search(r"Class:\s+(\S+)", header).group(1)
    machine = re.search(r"Machine:\s+(.+)", header).group(1).strip()
    if elf_class != "ELF64" or machine != "AArch64":
        problems.append(f"{elf_class} {machine}, not ELF64 AArch64")
    m = re.search(r"Requesting program interpreter: (.+?)\]", readelf(tool, "-l", path))
    interp = m.group(1) if m else None
    if interp != INTERP:
        problems.append(f"interpreter {interp}, not {INTERP}")
    dynamic = readelf(tool, "-d", path)
    needed = re.findall(r"\(NEEDED\)\s+Shared library: \[(.+?)\]", dynamic)
    for lib in needed:
        if lib not in ALLOWED:
            problems.append(f"needs {lib}, which not every board's firmware has")
    for kind, value in re.findall(r"\((RPATH|RUNPATH)\)\s+Library r(?:un)?path: \[(.*?)\]", dynamic):
        problems.append(f"{kind} {value}")
    _, needs = version_sections(tool, path)
    newest = {}
    for lib, versions in sorted(needs.items()):
        for v in sorted(versions):
            family, number = split_version(v)
            if family == "ZLIB":
                if v not in zlib_defs:
                    floor = max(zlib_defs, key=lambda d: split_version(d)[1] or ())
                    problems.append(f"{v} from {lib}: the floor zlib defines up to {floor}")
            elif family in CEILING and number is not None and number > CEILING[family]:
                problems.append(f"{v} from {lib}: above {family}_{'.'.join(map(str, CEILING[family]))}")
            if number is not None and (family not in newest or number > split_version(newest[family])[1]):
                newest[family] = v
    data = open(path, "rb").read()
    for text in forbid:
        if text and text.encode() in data:
            problems.append(f"contains the build path {text}")
    print(f"{path}: {elf_class} {machine}, interpreter {interp}")
    print(f"  needs: {' '.join(needed)}")
    print(f"  newest versions: {' '.join(newest[f] for f in sorted(newest))}")
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--readelf", required=True)
    ap.add_argument("--zlib", required=True, help="the floor libz.so the program was linked against")
    ap.add_argument("--forbid", action="append", default=[])
    ap.add_argument("files", nargs="+")
    args = ap.parse_args()
    zlib_defs = {d for d in version_sections(args.readelf, args.zlib)[0] if d.startswith("ZLIB_")}
    if not zlib_defs:
        sys.exit(f"{args.zlib} defines no ZLIB_ versions")
    failed = False
    for path in args.files:
        problems = check(args.readelf, path, zlib_defs, args.forbid)
        for p in problems:
            print(f"  FLOOR VIOLATION: {p}")
        failed = failed or bool(problems)
    print("floor: FAILED" if failed else "floor: OK (glibc 2.33, GLIBCXX 3.4.28, CXXABI 1.3.12, GCC 7.0.0, zlib 1.2.8)")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
