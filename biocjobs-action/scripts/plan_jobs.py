#!/usr/bin/env python3
"""List the jobs a package declares and the image each one runs in.

Usage: plan_jobs.py PACKAGE_DIR BUILT_IMAGE [JOB ...]

Prints "<job>\t<image>" per job, where <image> is the container the job's
YAML declares. It is empty when the job declares none, or declares
BUILT_IMAGE (compared without tag or digest): those jobs use the image the
action builds. With JOB arguments only those jobs are listed.
"""
from __future__ import annotations

import pathlib
import sys

import yaml


def repository(image: str) -> str:
    name = image.split("@", 1)[0]
    head, _, last = name.rpartition("/")
    last = last.split(":", 1)[0]
    return f"{head}/{last}".lower() if head else last.lower()


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    jobs_dir = pathlib.Path(argv[1]) / "inst" / "biocjobs"
    built = repository(argv[2])
    wanted = argv[3:]

    declared: dict[str, str] = {}
    paths = sorted(p for p in jobs_dir.glob("*") if p.suffix in (".yaml", ".yml"))
    for path in paths:
        spec = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        name = str(spec.get("name", ""))
        container = spec.get("container")
        image = "" if container is None else str(container).strip()
        if image and repository(image) == built:
            image = ""
        declared[name] = image

    if not declared:
        print(f"::error::No jobs declared under {jobs_dir}.", file=sys.stderr)
        return 1
    unknown = [job for job in wanted if job not in declared]
    if unknown:
        print(f"::error::Not declared by the package: {', '.join(unknown)}.", file=sys.stderr)
        return 1
    for job in wanted or declared:
        print(f"{job}\t{declared[job]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
