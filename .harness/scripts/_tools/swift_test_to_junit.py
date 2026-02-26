#!/usr/bin/env python3
"""Convert XCTest console output from `swift test` into JUnit XML."""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

CASE_RESULT_RE = re.compile(
    r"^Test Case '-\[(?P<classname>[^\s]+)\s+(?P<name>[^\]]+)\]' "
    r"(?P<result>passed|failed) \((?P<seconds>[0-9.]+) seconds\)\.$"
)
TEST_CASE_START_RE = re.compile(r"^Test Case '-\[(?P<classname>[^\s]+)\s+(?P<name>[^\]]+)\]' started\.$")
FAILURE_LINE_RE = re.compile(r"^.+:\d+:\s+error:\s+.+$")


@dataclass
class TestCaseResult:
    classname: str
    name: str
    seconds: float = 0.0
    failed: bool = False
    failure_lines: list[str] = field(default_factory=list)

    @property
    def key(self) -> str:
        return f"{self.classname}::{self.name}"


def parse_test_log(lines: list[str]) -> list[TestCaseResult]:
    cases: dict[str, TestCaseResult] = {}
    current_key: str | None = None

    for raw in lines:
        line = raw.rstrip("\n")

        started = TEST_CASE_START_RE.match(line)
        if started:
            classname = started.group("classname")
            name = started.group("name")
            current_key = f"{classname}::{name}"
            cases.setdefault(current_key, TestCaseResult(classname=classname, name=name))
            continue

        result = CASE_RESULT_RE.match(line)
        if result:
            classname = result.group("classname")
            name = result.group("name")
            key = f"{classname}::{name}"
            case = cases.setdefault(key, TestCaseResult(classname=classname, name=name))
            case.seconds = float(result.group("seconds"))
            case.failed = result.group("result") == "failed"
            current_key = None
            continue

        if current_key and FAILURE_LINE_RE.match(line):
            cases[current_key].failure_lines.append(line)

    return sorted(cases.values(), key=lambda c: (c.classname, c.name))


def build_junit(cases: list[TestCaseResult]) -> ET.ElementTree:
    failures = sum(1 for case in cases if case.failed)
    total_time = sum(case.seconds for case in cases)

    testsuites = ET.Element("testsuites")
    testsuite = ET.SubElement(
        testsuites,
        "testsuite",
        attrib={
            "name": "XCTestResults",
            "errors": "0",
            "tests": str(len(cases)),
            "failures": str(failures),
            "skipped": "0",
            "time": f"{total_time:.6f}",
        },
    )

    for case in cases:
        testcase = ET.SubElement(
            testsuite,
            "testcase",
            attrib={
                "classname": case.classname,
                "name": case.name,
                "time": f"{case.seconds:.6f}",
            },
        )
        if case.failed:
            message = "\n".join(case.failure_lines) if case.failure_lines else "Test failed"
            failure = ET.SubElement(testcase, "failure", attrib={"message": "XCTest failure"})
            failure.text = message

    return ET.ElementTree(testsuites)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="Path to captured `swift test` output log")
    parser.add_argument("--output", required=True, help="Path to write JUnit XML")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.is_file():
        print(f"Input file not found: {input_path}", file=sys.stderr)
        return 1

    lines = input_path.read_text(encoding="utf-8", errors="replace").splitlines()
    cases = parse_test_log(lines)
    junit = build_junit(cases)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(junit, space="  ")  # type: ignore[attr-defined]
    junit.write(output_path, encoding="utf-8", xml_declaration=True)

    print(f"Wrote JUnit XML: {output_path} ({len(cases)} tests)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
