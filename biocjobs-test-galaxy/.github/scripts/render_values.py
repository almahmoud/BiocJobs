#!/usr/bin/env python3
"""Render tool wrappers into Helm values.

Usage:
  render_values.py --values OUT.json --manifest OUT.tsv --skipped OUT.tsv \\
    main=DIRECTORY [pr-<number>=DIRECTORY ...]

Sources are applied in order. A pull request may replace a tool from main. A pull
request with invalid tools, or with a tool another pull request already deploys, is
skipped and listed in the --skipped file. Invalid tools on main stop the render.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from validate_tools import Problems, check_tree  # noqa: E402

TOOL_DIR = "/galaxy/server/biocjobs-tools"


def mapping(content: str) -> dict:
    return {
        "content": content,
        # With tpl enabled the chart would evaluate the wrapper as a Helm template.
        "tpl": False,
        "useSecret": False,
        "applyToWeb": True,
        "applyToJob": True,
        "applyToWorkflow": True,
        "applyToCelery": True,
        "applyToSetupJob": False,
        "applyToNginx": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--values", required=True, type=pathlib.Path)
    parser.add_argument("--manifest", required=True, type=pathlib.Path)
    parser.add_argument("--skipped", required=True, type=pathlib.Path)
    parser.add_argument("sources", nargs="+", metavar="LABEL=DIRECTORY")
    args = parser.parse_args()

    chosen: dict[str, tuple[str, str, pathlib.Path]] = {}
    skipped: list[tuple[str, str]] = []
    for spec in args.sources:
        label, sep, directory = spec.partition("=")
        if not sep or not label or not directory:
            parser.error(f"expected LABEL=DIRECTORY, got {spec!r}")

        problems = Problems()
        tools = check_tree(pathlib.Path(directory), problems)
        if problems.count:
            if label == "main":
                return 1
            print(f"::warning::Skipping {label}: invalid tools")
            skipped.append((label, "invalid tools"))
            continue

        conflicts = sorted(tool_id for tool_id, _, _ in tools if tool_id in chosen and chosen[tool_id][0] != "main")
        if conflicts:
            owners = ", ".join(f"{tool_id} ({chosen[tool_id][0]})" for tool_id in conflicts)
            print(f"::warning::Skipping {label}: already deployed by {owners}")
            skipped.append((label, f"already deployed by {owners}"))
            continue

        for tool_id, version, path in tools:
            chosen[tool_id] = (label, version, path)

    # Keeps the tool directory present when no tools are deployed.
    files = {f"{TOOL_DIR}/README": mapping("Tools deployed from biocjobs-test-galaxy.\n")}
    for tool_id, (_, _, path) in sorted(chosen.items()):
        files[f"{TOOL_DIR}/{tool_id}.xml"] = mapping(path.read_text(encoding="utf-8"))

    args.values.write_text(json.dumps({"extraFileMappings": files}, indent=2) + "\n", encoding="utf-8")
    with args.manifest.open("w", encoding="utf-8") as manifest:
        for tool_id, (label, version, _) in sorted(chosen.items()):
            manifest.write(f"{tool_id}\t{version}\t{label}\n")
    with args.skipped.open("w", encoding="utf-8") as report:
        for label, reason in skipped:
            report.write(f"{label}\t{reason}\n")
    print(f"Rendered {len(chosen)} tool(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
