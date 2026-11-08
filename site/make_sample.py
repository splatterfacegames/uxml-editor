#!/usr/bin/env python3
"""Zip the sample project of the hosted editor.

The site opens it with /editor/?sample=sample (EdWebHost.open_sample).
The sample joins three fixture projects into one Unity-style project:
menu (Menu.uxml, CRLF), options (Options.uxml, an image asset) and
nested-styles (Nested.uxml, @import across folders). The fixture bytes are
copied as they are.

  python3 site/make_sample.py <out.zip>
"""
import os
import sys
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = ["menu", "options", "nested-styles"]
TOP = "sample"
SKIP_SUFFIXES = (".import", ".uid")


def main(out):
    seen = {}
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name in FIXTURES:
            root = os.path.join(REPO, "fixtures", "projects", name)
            for dirpath, dirnames, filenames in os.walk(root):
                dirnames.sort()
                for f in sorted(filenames):
                    if f.endswith(SKIP_SUFFIXES) or f.startswith("."):
                        continue
                    path = os.path.join(dirpath, f)
                    rel = os.path.relpath(path, root).replace(os.sep, "/")
                    if rel in seen:
                        raise SystemExit(f"{rel} is in both {seen[rel]} and {name}")
                    seen[rel] = name
                    z.write(path, TOP + "/" + rel)
    print(f"{out}: {len(seen)} files from {', '.join(FIXTURES)}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "site/dist/editor/samples/sample.zip")
