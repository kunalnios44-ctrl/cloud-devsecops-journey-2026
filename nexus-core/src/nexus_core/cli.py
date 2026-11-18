"""Command-line interface for NORDIC NEXUS Core."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from nexus_core.policy import evaluate_inventory


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate a normalized cloud inventory JSON file.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    evaluate = subparsers.add_parser("evaluate", help="Run the local policy checks")
    evaluate.add_argument("inventory", type=Path, help="Path to inventory JSON")
    args = parser.parse_args()

    try:
        document = json.loads(args.inventory.read_text(encoding="utf-8"))
        findings = evaluate_inventory(document)
        report = {
            "engine": "nordic-nexus-core",
            "version": "0.1.0",
            "summary": {
                "total": len(findings),
                "passed": sum(item.status == "pass" for item in findings),
                "failed": sum(item.status == "fail" for item in findings),
            },
            "findings": [item.to_dict() for item in findings],
        }
        print(json.dumps(report, indent=2))
        return 1 if report["summary"]["failed"] else 0
    except (OSError, json.JSONDecodeError, TypeError, ValueError) as exc:
        print(f"nexus-core: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
