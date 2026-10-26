#!/usr/bin/env python3
"""Repository hygiene and documentation-link check for UltraBlade.

Checks all tracked-source text for UTF-8/no BOM/no CR, and resolves every relative
Markdown link in the repo. Generated/third-party reference folders are skipped.
Standard library only.

Usage: python scripts/check_repo.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", ".godot", "build", "artifacts", "reference", "__pycache__", "captures"}
BINARY_EXTS = {
    ".png", ".jpg", ".jpeg", ".webp", ".gif", ".ico", ".ttf", ".otf",
    ".wav", ".mp3", ".ogg", ".glb", ".gltf", ".bin", ".exe", ".pck", ".zip", ".7z",
}
LINK_RE = re.compile(r"!?\[[^\]]*\]\(\s*(<[^>]*>|[^)\s]*)(?:\s+\"[^\"]*\")?\s*\)")
SCHEME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def files():
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(ROOT)
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        yield path, rel


def check_text():
    problems = []
    text = 0
    binary = 0
    for path, rel in files():
        data = path.read_bytes()
        if path.suffix.lower() in BINARY_EXTS:
            binary += 1
            continue
        text += 1
        if data.startswith(b"\xef\xbb\xbf") or data.startswith(b"\xff\xfe") or data.startswith(b"\xfe\xff"):
            problems.append(f"{rel}: BOM")
            continue
        if b"\r" in data:
            problems.append(f"{rel}: carriage return")
        try:
            data.decode("utf-8")
        except UnicodeDecodeError as exc:
            problems.append(f"{rel}: not valid UTF-8 at byte {exc.start}")
    return text, binary, problems


def check_links():
    problems = []
    checked = 0
    for path, rel in files():
        if path.suffix.lower() != ".md":
            continue
        in_fence = False
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.lstrip()
            if stripped.startswith("```") or stripped.startswith("~~~"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for match in LINK_RE.finditer(line):
                target = match.group(1).strip()
                if target.startswith("<") and target.endswith(">"):
                    target = target[1:-1].strip()
                if not target or target.startswith("#") or SCHEME_RE.match(target):
                    continue
                checked += 1
                path_part = unquote(target.split("#", 1)[0].split("?", 1)[0])
                if path_part and not (path.parent / path_part).exists():
                    problems.append(f"{rel}:{number}: {target}")
    return checked, problems


def main() -> int:
    text, binary, text_problems = check_text()
    checked, link_problems = check_links()
    problems = text_problems + link_problems
    if problems:
        for problem in problems:
            print("FAIL", problem)
        print(f"FAIL {len(problems)} problem(s)")
        return 1
    print(f"PASS text: {text} UTF-8/no-BOM/no-CR text files; {binary} binary files skipped")
    print(f"PASS links: {checked} relative Markdown links resolve")
    print("CHECK_REPO_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
