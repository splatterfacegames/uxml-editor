#!/usr/bin/env python3
"""Pin godot-uxml: copy addons/godot_uxml and the parity cases at one commit.

The editor uses a synced copy of the addon, not a submodule. The copy holds
the native Windows DLL that the godot-uxml repository commits, so a plain
clone of the editor runs without a second checkout.

Usage:
    python tools/update_godot_uxml.py --ref <commit-or-branch> [--source <path-or-url>]
    python tools/update_godot_uxml.py --verify     (CI: the copy matches the pin)

--source defaults to https://github.com/splatterfacegames/godot-uxml.git. A local
checkout is read with `git archive`, so the files come from the commit,
never from the working tree. The script writes godot-uxml.pin with the
resolved commit.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import shutil
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = "https://github.com/splatterfacegames/godot-uxml.git"
ADDON = "addons/godot_uxml"
CASES = "bench/parity/cases"
CASES_DEST = REPO / "tests" / "fixtures" / "godot-uxml-parity"
CASE_SUFFIXES = {".uxml", ".uss"}


def git(*args: str, cwd: Path | None = None) -> bytes:
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True).stdout


def checkout_for(source: str, ref: str, scratch: Path) -> Path:
    path = Path(source)
    if path.is_dir() and (path / ".git").exists():
        return path
    clone = scratch / "godot-uxml"
    git("clone", "--quiet", "--filter=blob:none", "--no-checkout", source, str(clone))
    git("fetch", "--quiet", "origin", ref, cwd=clone)
    return clone


def extract(checkout: Path, commit: str, prefix: str) -> dict[str, bytes]:
    # No eol conversion (core.autocrlf): the blobs of the commit, byte for byte.
    data = git("-c", "core.autocrlf=false", "-c", "core.eol=lf", "archive", "--format=tar", commit, prefix, cwd=checkout)
    files: dict[str, bytes] = {}
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for member in tar.getmembers():
            if member.isfile():
                handle = tar.extractfile(member)
                assert handle is not None
                files[member.name] = handle.read()
    return files


def write_tree(files: dict[str, bytes], prefix: str, dest: Path, keep) -> int:
    if dest.exists():
        shutil.rmtree(dest)
    count = 0
    for name, blob in sorted(files.items()):
        rel = name[len(prefix):].lstrip("/")
        if not keep(rel):
            continue
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(blob)
        count += 1
    return count


def tree_hash(root: Path) -> tuple[int, str]:
    """SHA-256 over the sorted relative paths and bytes of every file under root."""
    h = hashlib.sha256()
    count = 0
    # Sort by the POSIX text of the path: a Windows Path sorts without case.
    files = sorted((p.relative_to(root).as_posix(), p) for p in root.rglob("*") if p.is_file())
    for rel, f in files:
        h.update(rel.encode() + b"\0" + f.read_bytes() + b"\0")
        count += 1
    return count, h.hexdigest()


def verify() -> int:
    """Check the addon copy against godot-uxml.pin (no network: the pin has the hash)."""
    pin = dict(
        line.split("=", 1)
        for line in (REPO / "godot-uxml.pin").read_text().splitlines()
        if "=" in line and not line.startswith("#")
    )
    count, digest = tree_hash(REPO / ADDON)
    ok = str(count) == pin.get("addon_files") and digest == pin.get("addon_sha256")
    print(f"godot-uxml {pin.get('commit', '?')[:7]}: {count} files, sha256 {digest[:16]}... "
          + ("matches the pin" if ok else f"DIFFERS from the pin ({pin.get('addon_files')} files, {pin.get('addon_sha256', '?')[:16]}...)"))
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ref", help="godot-uxml commit, tag or branch")
    parser.add_argument("--source", default=DEFAULT_SOURCE, help="local checkout or clone URL")
    parser.add_argument("--verify", action="store_true", help="check the addon copy against the pin and exit")
    args = parser.parse_args()
    if args.verify:
        return verify()
    if not args.ref:
        parser.error("--ref is required")

    with tempfile.TemporaryDirectory() as tmp:
        checkout = checkout_for(args.source, args.ref, Path(tmp))
        commit = git("rev-parse", f"{args.ref}^{{commit}}", cwd=checkout).decode().strip()
        stamp = git("show", "-s", "--format=%cI", commit, cwd=checkout).decode().strip()
        addon = extract(checkout, commit, ADDON)
        cases = extract(checkout, commit, CASES)

    addon_count = write_tree(addon, ADDON, REPO / ADDON, lambda rel: True)
    case_count = write_tree(
        cases, CASES, CASES_DEST, lambda rel: Path(rel).suffix in CASE_SUFFIXES
    )
    (CASES_DEST / ".gdignore").write_text("")
    _, digest = tree_hash(REPO / ADDON)
    pin = (
        "# godot-uxml pin. Written by tools/update_godot_uxml.py. Do not edit.\n"
        f"commit={commit}\n"
        f"committed={stamp}\n"
        f"source={args.source if not Path(args.source).is_dir() else DEFAULT_SOURCE}\n"
        f"synced={datetime.now(timezone.utc).replace(microsecond=0).isoformat()}\n"
        f"addon_files={addon_count}\n"
        f"addon_sha256={digest}\n"
        f"parity_cases={case_count}\n"
    )
    (REPO / "godot-uxml.pin").write_text(pin, newline="\n")
    print(pin, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
