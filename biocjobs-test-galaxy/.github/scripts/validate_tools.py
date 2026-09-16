#!/usr/bin/env python3
"""Check tool wrappers against the repository rules.

Usage: validate_tools.py DIRECTORY [DIRECTORY ...]

Prints "<id>\t<version>\t<path>" for each valid tool. Exits 1 if any file breaks a rule.
"""
from __future__ import annotations

import pathlib
import re
import sys
import xml.etree.ElementTree as ET

TOOL_ID = re.compile(r"^[a-z][a-z0-9_]{1,31}$")
VERSION = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.+_-]{0,63}$")
MAX_BYTES = 64 * 1024
GALAXY_VERSION = (24, 1)
# Characters YAML treats as line breaks or that have no place in a wrapper.
FORBIDDEN_CHARACTERS = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u2028\u2029]")
ALLOWED_TOP_LEVEL = {"README.md", ".gitkeep"}
UNSUPPORTED_TOOL_TYPES = {"interactive", "data_source", "data_source_async", "manage_data"}


class Problems:
    def __init__(self) -> None:
        self.count = 0

    def add(self, path: pathlib.Path, message: str) -> None:
        self.count += 1
        print(f"::error file={path}::{message}", file=sys.stderr)


def check_tree(root: pathlib.Path, problems: Problems) -> list[tuple[str, str, pathlib.Path]]:
    tools: list[tuple[str, str, pathlib.Path]] = []
    if not root.is_dir():
        problems.add(root, "directory not found")
        return tools

    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            problems.add(path, "symbolic links are not allowed")
            continue
        if path.is_dir():
            continue
        relative = path.relative_to(root)
        if len(relative.parts) == 1 and relative.name in ALLOWED_TOP_LEVEL:
            continue
        if len(relative.parts) != 2 or relative.parts[1] != f"{relative.parts[0]}.xml":
            problems.add(path, "only <tool_id>/<tool_id>.xml files are allowed")
            continue
        tool = check_file(path, relative.parts[0], problems)
        if tool:
            tools.append(tool)
    return tools


def check_file(path: pathlib.Path, directory: str, problems: Problems) -> tuple[str, str, pathlib.Path] | None:
    if not TOOL_ID.match(directory):
        problems.add(path, f"'{directory}' is not a valid tool id: use 2-32 lowercase letters, digits and underscores, starting with a letter")
        return None

    raw = path.read_bytes()
    if len(raw) > MAX_BYTES:
        problems.add(path, f"file is {len(raw)} bytes; the limit is {MAX_BYTES}")
        return None
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        problems.add(path, "file must be UTF-8")
        return None
    if FORBIDDEN_CHARACTERS.search(text):
        problems.add(path, "file contains control characters or Unicode line separators")
        return None
    if re.search(r"<!(DOCTYPE|ENTITY)", text, re.IGNORECASE):
        problems.add(path, "DOCTYPE and ENTITY declarations are not allowed")
        return None

    try:
        root = ET.fromstring(text)
    except ET.ParseError as exc:
        problems.add(path, f"invalid XML: {exc}")
        return None
    if root.tag != "tool":
        problems.add(path, f"root element must be <tool>, not <{root.tag}>")
        return None

    tool_id = root.get("id", "")
    version = root.get("version", "")
    valid = True
    if tool_id != directory:
        problems.add(path, f"tool id '{tool_id}' does not match directory '{directory}'")
        valid = False
    if not VERSION.match(version):
        problems.add(path, "missing or invalid version")
        valid = False
    if not root.get("name"):
        problems.add(path, "missing name")
        valid = False
    profile = root.get("profile")
    if profile is not None:
        parts = re.findall(r"\d+", profile)[:2]
        if len(parts) < 2 or tuple(int(p) for p in parts) > GALAXY_VERSION:
            problems.add(path, f"profile '{profile}' is newer than the test Galaxy ({GALAXY_VERSION[0]}.{GALAXY_VERSION[1]})")
            valid = False
    if root.get("tool_type", "default") in UNSUPPORTED_TOOL_TYPES:
        problems.add(path, f"tool_type '{root.get('tool_type')}' is not supported")
        valid = False
    if root.find(".//import") is not None:
        problems.add(path, "macro imports are not supported")
        valid = False
    if "__tool_directory__" in text:
        problems.add(path, "$__tool_directory__ is not supported; only the XML file is deployed")
        valid = False
    return (tool_id, version, path) if valid else None


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    problems = Problems()
    for directory in argv[1:]:
        for tool_id, version, path in check_tree(pathlib.Path(directory), problems):
            print(f"{tool_id}\t{version}\t{path}")
    return 1 if problems.count else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
