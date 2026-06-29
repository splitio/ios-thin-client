#!/usr/bin/env python3
"""Convert `llvm-cov export -format=json` data to SonarQube Generic Coverage XML."""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def normalize_path(path: str, root: Path) -> str:
    candidate = Path(path)
    try:
        return str(candidate.resolve().relative_to(root.resolve()))
    except Exception:
        return path


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def collect_line_coverage(segments: list[list]) -> dict[int, bool]:
    """Build line coverage from llvm segment rows.

    Segment row shape is usually:
      [line, col, count, hasCount, isRegionEntry, ...]
    We only include executable lines where hasCount is truthy.
    """

    lines: dict[int, bool] = {}
    for seg in segments:
        if len(seg) < 4:
            continue
        line_no = int(seg[0])
        count = int(seg[2])
        has_count = bool(seg[3])
        if not has_count or line_no <= 0:
            continue
        covered = count > 0
        lines[line_no] = lines.get(line_no, False) or covered
    return lines


def build_xml(payload: dict, root_path: Path, exclude_pattern: re.Pattern[str] | None) -> ET.ElementTree:
    coverage = ET.Element("coverage", attrib={"version": "1"})

    data_blocks = payload.get("data", [])
    file_entries: dict[str, dict[int, bool]] = {}

    for block in data_blocks:
        for file_info in block.get("files", []):
            filename = file_info.get("filename")
            segments = file_info.get("segments")
            if not filename or not isinstance(segments, list):
                continue
            normalized = normalize_path(filename, root_path)
            if exclude_pattern and exclude_pattern.search(normalized):
                continue
            covered_lines = collect_line_coverage(segments)
            if not covered_lines:
                continue
            existing = file_entries.setdefault(normalized, {})
            for line_no, is_covered in covered_lines.items():
                existing[line_no] = existing.get(line_no, False) or is_covered

    for filepath in sorted(file_entries):
        file_node = ET.SubElement(coverage, "file", attrib={"path": filepath})
        for line_no in sorted(file_entries[filepath]):
            ET.SubElement(
                file_node,
                "lineToCover",
                attrib={
                    "lineNumber": str(line_no),
                    "covered": "true" if file_entries[filepath][line_no] else "false",
                },
            )

    return ET.ElementTree(coverage)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="Path to llvm-cov JSON export file")
    parser.add_argument("--output", required=True, help="Path to write Sonar Generic Coverage XML")
    parser.add_argument(
        "--repo-root",
        default=".",
        help="Repository root used to normalize absolute file paths (default: current directory)",
    )
    parser.add_argument(
        "--exclude-regex",
        default=r"(^|/)\.build/",
        help="Regex for files to exclude from coverage XML (default excludes .build artifacts).",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)
    repo_root = Path(args.repo_root)

    if not input_path.is_file():
        print(f"Input file not found: {input_path}", file=sys.stderr)
        return 1

    payload = load_json(input_path)
    exclude_pattern = re.compile(args.exclude_regex) if args.exclude_regex else None
    xml_tree = build_xml(payload, repo_root, exclude_pattern)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(xml_tree, space="  ")  # type: ignore[attr-defined]
    xml_tree.write(output_path, encoding="utf-8", xml_declaration=True)
    print(f"Wrote Sonar generic coverage XML: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
