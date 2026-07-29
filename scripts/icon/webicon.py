#!/usr/bin/env python3
"""Composite a variant's layers into one flat SVG for the landing page.

The site uses the same mark as the app for its favicon and nav wordmark, and
before this existed the two drifted: docs/ shipped a placeholder from an earlier
design while the app had moved on. Generating it from the same source as the app
icon is what keeps them honest.

Usage: webicon.py <variant-dir> <out.svg>
"""
import json, pathlib, re, sys

CREAM = "#F4F1E9"


def main(src: pathlib.Path, out: pathlib.Path) -> None:
    cfg = json.loads((src / "icon.json").read_text())
    # icon.json lists layers top-first; composite in reverse so z-order matches.
    names = [l["image-name"] for l in cfg["groups"][0]["layers"]][::-1]
    inner = ""
    for n in names:
        body = (src / "Assets" / n).read_text()
        inner += re.sub(r"^.*?<svg[^>]*>|</svg>\s*$", "", body, flags=re.S)
    out.write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
        f'width="1024" height="1024"><rect width="1024" height="1024" fill="{CREAM}"/>'
        f"{inner}</svg>")
    print(f"  composited {len(names)} layer(s) -> {out.name}")


if __name__ == "__main__":
    main(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
