#!/usr/bin/env python3
"""Validate the ASOS package lists against the current Arch Linux repositories.

  scripts/check-packages.py [--cache DIR] [--mirror URL] [--no-aur]

Checks, without root and without Arch Linux:
  * every package in archiso/packages.x86_64 exists (or is provided by one);
  * the full dependency closure resolves; prints provider choices pacman
    would make on its own (so they can be pinned explicitly);
  * no two packages in the closure conflict (version-aware);
  * no two packages in the closure own the same file;
  * every AUR package in archiso/packages.aur exists and its run/build
    dependencies resolve from the official repos (or earlier AUR entries).
Exit code 1 if anything is wrong.
"""
import argparse
import collections
import json
import os
import re
import sys
import tarfile
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPOS = ["core", "extra", "multilib"]


def fetch(url, dest):
    req = urllib.request.Request(url, headers={"User-Agent": "asos-check-packages"})
    with urllib.request.urlopen(req, timeout=300) as r, open(dest + ".part", "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    os.replace(dest + ".part", dest)


def parse_desc(text):
    fields = {}
    for block in text.strip().split("\n\n"):
        lines = block.strip().split("\n")
        if lines and lines[0].startswith("%"):
            fields[lines[0].strip("%")] = lines[1:]
    return fields


def read_list(path):
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                out.append(line)
    return out


def dep_name(dep):
    return re.split(r"[<>=]", dep, maxsplit=1)[0].strip()


def _segments(v):
    return [int(x) if x.isdigit() else x for x in re.findall(r"\d+|[a-zA-Z]+", v)]


def vercmp(a, b):
    """Close approximation of pacman's vercmp (epoch:version-release)."""
    def split(v):
        epoch, ver = (v.split(":", 1) if ":" in v else ("0", v))
        ver, _, rel = ver.partition("-")
        return int(epoch or 0), ver, rel

    ea, va, ra = split(a)
    eb, vb, rb = split(b)
    if ea != eb:
        return (ea > eb) - (ea < eb)
    for x, y in ((va, vb), (ra, rb)):
        if not x or not y:
            continue
        sx, sy = _segments(x), _segments(y)
        for i, j in zip(sx, sy):
            if type(i) is not type(j):
                return 1 if isinstance(i, int) else -1
            if i != j:
                return (i > j) - (i < j)
        if len(sx) != len(sy):
            return (len(sx) > len(sy)) - (len(sx) < len(sy))
    return 0


def satisfies(version, constraint):
    m = re.match(r"^([^<>=]+)(<=|>=|<|>|=)?(.*)$", constraint)
    if not m or not m.group(2):
        return True
    c = vercmp(version, m.group(3))
    return {"<": c < 0, "<=": c <= 0, ">": c > 0, ">=": c >= 0, "=": c == 0}[m.group(2)]


class Repo:
    def __init__(self, cache, mirror):
        self.pkgs, self.order = {}, []
        for repo in REPOS:
            path = os.path.join(cache, repo + ".files")
            if not os.path.exists(path):
                print(f":: downloading {repo}.files", file=sys.stderr)
                fetch(f"{mirror}/{repo}/os/x86_64/{repo}.files", path)
            entries = collections.defaultdict(dict)
            with tarfile.open(path) as t:
                for m in t.getmembers():
                    if m.isfile() and "/" in m.name:
                        d, fn = m.name.split("/", 1)
                        entries[d][fn] = t.extractfile(m).read().decode()
            for files in entries.values():
                desc = parse_desc(files["desc"])
                name = desc["NAME"][0]
                if name in self.pkgs:
                    continue
                self.pkgs[name] = {
                    "repo": repo,
                    "version": desc["VERSION"][0],
                    "depends": desc.get("DEPENDS", []),
                    "provides": desc.get("PROVIDES", []),
                    "conflicts": desc.get("CONFLICTS", []),
                    "size": int(desc.get("ISIZE", ["0"])[0]),
                    "files": [f for f in parse_desc(files.get("files", "")).get("FILES", []) if not f.endswith("/")],
                }
                self.order.append(name)
        self.providers = collections.defaultdict(list)
        for name in self.order:
            for p in self.pkgs[name]["provides"]:
                self.providers[dep_name(p)].append(name)

    def provides(self, pkg, dep):
        """Does pkg satisfy dependency string dep (name + optional version)?"""
        name = dep_name(dep)
        info = self.pkgs[pkg]
        if pkg == name:
            return satisfies(info["version"], dep)
        for p in info["provides"]:
            if dep_name(p) == name:
                if "=" in p and re.search(r"[<>=]", dep):
                    return satisfies(p.split("=", 1)[1], dep)
                return True
        return False

    def find(self, dep):
        name = dep_name(dep)
        if name in self.pkgs and self.provides(name, dep):
            return name, []
        cands = [p for p in self.providers.get(name, []) if self.provides(p, dep)]
        return (cands[0], cands) if cands else (None, [])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--cache", default=os.path.join(ROOT, "work", "pkgcheck"))
    ap.add_argument("--mirror", default="https://geo.mirror.pkgbuild.com")
    ap.add_argument("--list", default=os.path.join(ROOT, "archiso", "packages.x86_64"))
    ap.add_argument("--aur-list", default=os.path.join(ROOT, "archiso", "packages.aur"))
    ap.add_argument("--no-aur", action="store_true")
    args = ap.parse_args()
    os.makedirs(args.cache, exist_ok=True)

    repo = Repo(args.cache, args.mirror)
    errors = []

    targets = read_list(args.list)
    dupes = [t for t, n in collections.Counter(targets).items() if n > 1]
    if dupes:
        errors.append("duplicate entries: " + ", ".join(dupes))

    selected, choices = {}, set()
    for t in targets:
        pkg, cands = repo.find(t)
        if not pkg:
            errors.append(f"package not found: {t}")
        else:
            selected[pkg] = "explicit"
            if pkg != t:
                print(f"  note: '{t}' is provided by '{pkg}' — consider listing '{pkg}' directly")

    queue = list(selected)
    while queue:
        n = queue.pop()
        for dep in repo.pkgs[n]["depends"]:
            if any(repo.provides(s, dep) for s in selected):
                continue
            pkg, cands = repo.find(dep)
            if not pkg:
                errors.append(f"unresolvable dependency: {n} -> {dep}")
                continue
            if len(cands) > 1:
                choices.add((dep_name(dep), pkg, ", ".join(cands[:6])))
            selected[pkg] = n
            queue.append(pkg)

    for n in selected:
        for c in repo.pkgs[n]["conflicts"]:
            for o in selected:
                if o != n and repo.provides(o, c):
                    errors.append(f"conflict: {n} conflicts with {o} ({c})")

    owners = collections.defaultdict(list)
    for n in selected:
        for f in repo.pkgs[n]["files"]:
            owners[f].append(n)
    for f, o in sorted(owners.items()):
        if len(o) > 1:
            errors.append(f"file conflict: /{f} owned by {', '.join(o)}")

    size = sum(repo.pkgs[n]["size"] for n in selected)
    print(f"official: {len(targets)} listed, {len(selected)} with dependencies, "
          f"{size / 2**30:.1f} GiB installed")
    if choices:
        print("provider choices made automatically (pin one explicitly if the default is wrong):")
        for name, pkg, cands in sorted(choices):
            print(f"  {name:28} -> {pkg:28} [{cands}]")

    if not args.no_aur and os.path.exists(args.aur_list):
        aur = read_list(args.aur_list)
        q = urllib.parse.urlencode([("arg[]", a) for a in aur])
        req = urllib.request.Request(f"https://aur.archlinux.org/rpc/v5/info?{q}",
                                     headers={"User-Agent": "asos-check-packages"})
        with urllib.request.urlopen(req, timeout=60) as r:
            results = {p["Name"]: p for p in json.load(r)["results"]}
        built = set()
        for a in aur:
            info = results.get(a)
            if not info:
                errors.append(f"AUR package not found: {a}")
                continue
            if info.get("OutOfDate"):
                print(f"  note: AUR {a} is flagged out of date")
            for dep in info.get("Depends", []) + info.get("MakeDepends", []):
                name = dep_name(dep)
                if repo.find(dep)[0] or name in built or name in ("base-devel",):
                    continue
                errors.append(f"AUR {a}: dependency '{dep}' is neither official nor built earlier")
            built.add(a)
            for p in info.get("Provides", []):
                built.add(dep_name(p))
        print(f"aur: {len(aur)} packages checked")

    if errors:
        print("\nERRORS:")
        for e in errors:
            print("  " + e)
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
