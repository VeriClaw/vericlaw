#!/usr/bin/env python3
"""
SPARK Proof Regression Checker

Parses GNATprove JSON output and compares against a baseline.
Fails if unproved VCs increase.

Usage:
    python3 scripts/check_proof_regression.py \
        --current=gnatprove/gnatprove.out \
        --baseline=.proof-baseline.json

    # To update baseline after intentional changes:
    python3 scripts/check_proof_regression.py \
        --current=gnatprove/gnatprove.out \
        --update-baseline
"""

import json
import sys
import argparse
import os
from pathlib import Path


def parse_gnatprove_output(path: str) -> dict:
    """Parse GNATprove output directory for proof statistics."""
    stats = {
        "total_vcs": 0,
        "proved_vcs": 0,
        "unproved_vcs": 0,
        "timeouts": 0,
        "errors": 0,
        "flow_warnings": 0,
        "units": {}
    }

    # GNATprove writes per-unit .spark files in the output directory
    gnatprove_dir = Path(path)
    if gnatprove_dir.is_dir():
        for spark_file in gnatprove_dir.glob("*.spark"):
            try:
                with open(spark_file) as f:
                    data = json.load(f)
                unit_name = spark_file.stem
                unit_stats = {"proved": 0, "unproved": 0, "total": 0}
                
                if "proof" in data:
                    for proof_item in data["proof"]:
                        stats["total_vcs"] += 1
                        unit_stats["total"] += 1
                        if proof_item.get("result", {}).get("status") == "proved":
                            stats["proved_vcs"] += 1
                            unit_stats["proved"] += 1
                        elif proof_item.get("result", {}).get("status") == "timeout":
                            stats["timeouts"] += 1
                            stats["unproved_vcs"] += 1
                            unit_stats["unproved"] += 1
                        else:
                            stats["unproved_vcs"] += 1
                            unit_stats["unproved"] += 1
                
                if "flow" in data:
                    for flow_item in data["flow"]:
                        if flow_item.get("severity") == "warning":
                            stats["flow_warnings"] += 1
                
                stats["units"][unit_name] = unit_stats
            except (json.JSONDecodeError, KeyError):
                stats["errors"] += 1
                continue
    elif gnatprove_dir.is_file():
        # Single JSON report file
        try:
            with open(gnatprove_dir) as f:
                data = json.load(f)
            # Handle flat report format
            if isinstance(data, dict):
                stats["total_vcs"] = data.get("total", 0)
                stats["proved_vcs"] = data.get("proved", 0)
                stats["unproved_vcs"] = data.get("unproved", 0)
                stats["timeouts"] = data.get("timeouts", 0)
        except (json.JSONDecodeError, KeyError):
            stats["errors"] += 1

    return stats


def compare_with_baseline(current: dict, baseline: dict) -> tuple[bool, list[str]]:
    """Compare current proof stats against baseline. Returns (pass, messages)."""
    messages = []
    passed = True

    # Check if unproved VCs increased
    if current["unproved_vcs"] > baseline.get("unproved_vcs", 0):
        delta = current["unproved_vcs"] - baseline["unproved_vcs"]
        messages.append(f"REGRESSION: Unproved VCs increased by {delta} "
                       f"({baseline['unproved_vcs']} → {current['unproved_vcs']})")
        passed = False

    # Check if total VCs decreased (units removed?)
    if current["total_vcs"] < baseline.get("total_vcs", 0):
        delta = baseline["total_vcs"] - current["total_vcs"]
        messages.append(f"WARNING: Total VCs decreased by {delta} "
                       f"({baseline['total_vcs']} → {current['total_vcs']})")

    # Check for new timeouts
    if current["timeouts"] > baseline.get("timeouts", 0):
        delta = current["timeouts"] - baseline["timeouts"]
        messages.append(f"WARNING: Timeouts increased by {delta}")

    # Improvements
    if current["proved_vcs"] > baseline.get("proved_vcs", 0):
        delta = current["proved_vcs"] - baseline["proved_vcs"]
        messages.append(f"IMPROVEMENT: {delta} new VCs proved!")

    if not messages:
        messages.append("No changes in proof status")

    return passed, messages


def main():
    parser = argparse.ArgumentParser(description="SPARK proof regression checker")
    parser.add_argument("--current", required=True, help="Path to current GNATprove output")
    parser.add_argument("--baseline", default=".proof-baseline.json", help="Path to baseline JSON")
    parser.add_argument("--update-baseline", action="store_true", help="Update baseline with current stats")
    args = parser.parse_args()

    current = parse_gnatprove_output(args.current)

    print(f"=== SPARK Proof Statistics ===")
    print(f"Total VCs:    {current['total_vcs']}")
    print(f"Proved:       {current['proved_vcs']}")
    print(f"Unproved:     {current['unproved_vcs']}")
    print(f"Timeouts:     {current['timeouts']}")
    print(f"Flow warns:   {current['flow_warnings']}")
    if current['total_vcs'] > 0:
        pct = (current['proved_vcs'] / current['total_vcs']) * 100
        print(f"Proof rate:   {pct:.1f}%")
    print()

    if args.update_baseline:
        with open(args.baseline, 'w') as f:
            json.dump(current, f, indent=2)
        print(f"Baseline updated: {args.baseline}")
        return 0

    if not os.path.exists(args.baseline):
        print(f"No baseline found at {args.baseline}. Creating initial baseline.")
        with open(args.baseline, 'w') as f:
            json.dump(current, f, indent=2)
        print("Run again after making changes to check for regressions.")
        return 0

    with open(args.baseline) as f:
        baseline = json.load(f)

    passed, messages = compare_with_baseline(current, baseline)
    
    print("=== Regression Check ===")
    for msg in messages:
        prefix = "::error::" if "REGRESSION" in msg else "::warning::" if "WARNING" in msg else ""
        print(f"{prefix}{msg}")

    if not passed:
        print("\nFAILED: Proof regression detected!")
        return 1
    
    print("\nPASSED: No proof regressions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
